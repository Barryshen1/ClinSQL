WITH cohorts AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24 AS los_days,
        ad.hospital_expire_flag,
        p.gender,
        p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year)) BETWEEN 44 AND 54
        AND ad.hadm_id IN ( -- Patients with Intracranial Hemorrhage
            SELECT DISTINCT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                (di.icd_version = 9 AND (di.icd_code LIKE '430%' OR di.icd_code LIKE '431%' OR di.icd_code LIKE '432%'))
                OR (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%'))
        )
),
-- Step 2: Identify relevant diagnoses for risk score components and complications
all_diagnoses_for_cohort AS (
    SELECT
        di.subject_id,
        di.hadm_id,
        di.icd_version,
        di.icd_code
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN
        cohorts c ON di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id
),
ich_defining_diagnoses AS (
    SELECT DISTINCT subject_id, hadm_id, icd_code
    FROM all_diagnoses_for_cohort
    WHERE
        (icd_version = 9 AND (icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%'))
        OR (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
),
aki_diagnoses AS (
    SELECT DISTINCT subject_id, hadm_id, 1 AS aki_flag
    FROM all_diagnoses_for_cohort
    WHERE
        (icd_version = 9 AND icd_code LIKE '584%')
        OR (icd_version = 10 AND icd_code LIKE 'N17%')
),
hf_diagnoses AS (
    SELECT DISTINCT subject_id, hadm_id, 1 AS hf_flag
    FROM all_diagnoses_for_cohort
    WHERE
        (icd_version = 9 AND icd_code LIKE '428%')
        OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
cardiac_complications AS (
    SELECT DISTINCT subject_id, hadm_id, 1 AS cardiac_complication_flag
    FROM all_diagnoses_for_cohort
    WHERE
        (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code LIKE '427.5%' OR icd_code LIKE '428%')) -- Corrected '=' to 'LIKE' for '428%'
        OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code LIKE 'I46%' OR icd_code LIKE 'I50%')) -- Corrected '=' to 'LIKE' for 'I50%'
),
neurologic_complications AS (
    SELECT DISTINCT ad_neuro.subject_id, ad_neuro.hadm_id, 1 AS neuro_complication_flag
    FROM all_diagnoses_for_cohort ad_neuro
    WHERE
        -- Exclude the primary ICH diagnosis itself
        NOT EXISTS (
            SELECT 1 FROM ich_defining_diagnoses id WHERE id.subject_id = ad_neuro.subject_id AND id.hadm_id = ad_neuro.hadm_id AND id.icd_code = ad_neuro.icd_code
        ) AND
        ( -- Added outer parentheses for this OR grouping
            (ad_neuro.icd_version = 9 AND (ad_neuro.icd_code LIKE '434%' OR ad_neuro.icd_code LIKE '345%' OR ad_neuro.icd_code LIKE '331.3%' OR ad_neuro.icd_code LIKE '348.5%' OR ad_neuro.icd_code LIKE '348.4%'))
            OR (ad_neuro.icd_version = 10 AND (ad_neuro.icd_code LIKE 'I63%' OR ad_neuro.icd_code LIKE 'G40%' OR ad_neuro.icd_code LIKE 'G91%' OR ad_neuro.icd_code = 'G93.6' OR ad_neuro.icd_code = 'G93.5'))
        )
),
-- Step 3: Identify vasopressor usage
vasopressor_usage AS (
    SELECT DISTINCT ie.subject_id, ie.hadm_id, 1 AS vasopressor_flag
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ie.itemid = di.itemid
    JOIN cohorts c ON ie.subject_id = c.subject_id AND ie.hadm_id = c.hadm_id
    WHERE
        di.label IN (
            'Norepinephrine', 'Dopamine', 'Epinephrine', 'Vasopressin', 'Phenylephrine',
            'Norepinephrine Bitartrate', 'Epinephrine (Emergency)'
        )
),
-- Step 4: Aggregate components for risk score and gather outcomes for each patient
patient_outcomes AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.los_days,
        c.hospital_expire_flag,
        COUNT(DISTINCT
            CASE
                WHEN NOT EXISTS (SELECT 1 FROM ich_defining_diagnoses id WHERE id.subject_id = ad.subject_id AND id.hadm_id = ad.hadm_id AND id.icd_code = ad.icd_code)
                THEN ad.icd_code
                ELSE NULL
            END
        ) AS num_other_diagnoses, -- Number of unique diagnoses excluding ICH
        MAX(COALESCE(aki.aki_flag, 0)) AS has_aki,
        MAX(COALESCE(hf.hf_flag, 0)) AS has_hf,
        MAX(COALESCE(vp.vasopressor_flag, 0)) AS has_vasopressor,
        MAX(COALESCE(cc.cardiac_complication_flag, 0)) AS has_cardiac_complication,
        MAX(COALESCE(nc.neuro_complication_flag, 0)) AS has_neuro_complication
    FROM
        cohorts c
    LEFT JOIN
        all_diagnoses_for_cohort ad ON c.subject_id = ad.subject_id AND c.hadm_id = ad.hadm_id
    LEFT JOIN
        aki_diagnoses aki ON c.subject_id = aki.subject_id AND c.hadm_id = aki.hadm_id
    LEFT JOIN
        hf_diagnoses hf ON c.subject_id = hf.subject_id AND c.hadm_id = hf.hadm_id
    LEFT JOIN
        vasopressor_usage vp ON c.subject_id = vp.subject_id AND c.hadm_id = vp.hadm_id
    LEFT JOIN
        cardiac_complications cc ON c.subject_id = cc.subject_id AND c.hadm_id = cc.hadm_id
    LEFT JOIN
        neurologic_complications nc ON c.subject_id = nc.subject_id AND c.hadm_id = nc.hadm_id
    GROUP BY
        c.subject_id, c.hadm_id, c.los_days, c.hospital_expire_flag
),
-- Step 5: Calculate the composite risk score and assign quartiles
patient_scores_with_quartile AS (
    SELECT
        subject_id,
        hadm_id,
        los_days,
        hospital_expire_flag,
        has_cardiac_complication,
        has_neuro_complication,
        -- Define a composite risk score (illustrative example)
        -- Higher weight for more severe indicators
        (num_other_diagnoses * 0.5) + (has_aki * 3) + (has_hf * 2) + (has_vasopressor * 5) AS composite_risk_score,
        NTILE(4) OVER (ORDER BY (num_other_diagnoses * 0.5) + (has_aki * 3) + (has_hf * 2) + (has_vasopressor * 5)) AS risk_quartile
    FROM
        patient_outcomes
    -- Removed redundant WHERE clause, as components are guaranteed non-null by COALESCE and COUNT.
)
-- Step 6: Final aggregation by risk quartile to report requested metrics
SELECT
    risk_quartile,
    COUNT(DISTINCT subject_id) AS patient_count,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(DISTINCT subject_id), 2) AS in_hospital_mortality_rate,
    ROUND(SUM(has_cardiac_complication) * 100.0 / COUNT(DISTINCT subject_id), 2) AS cardiac_complication_rate,
    ROUND(SUM(has_neuro_complication) * 100.0 / COUNT(DISTINCT subject_id), 2) AS neurologic_complication_rate,
    APPROX_QUANTILES(
        CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END, 2
    )[OFFSET(1)] AS median_los_survivors -- Median LOS for survivors
FROM
    patient_scores_with_quartile
GROUP BY
    risk_quartile
ORDER BY
    risk_quartile;