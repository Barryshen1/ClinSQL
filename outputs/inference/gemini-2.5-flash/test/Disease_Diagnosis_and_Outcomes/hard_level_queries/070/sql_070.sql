WITH dvt_cohort AS (
    -- Step 1: Select females aged 59-69 with a DVT diagnosis
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.deathtime,
        ad.hospital_expire_flag,
        pa.gender,
        pa.anchor_age,
        pa.dod
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON ad.hadm_id = di.hadm_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 59 AND 69
        AND (
            (di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 4) = '4534') -- DVT ICD-9 codes (e.g., 45340, 45341, 45342, 45349)
            OR
            (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 4) = 'I824') -- DVT ICD-10 codes (e.g., I8240, I8241, I8242, I824Y, I824Z)
        )
),
dvt_cohort_comorbidities AS (
    -- Step 2: Calculate comorbidity score for each admission in the DVT cohort
    -- Simplified comorbidity score based on presence of common chronic conditions
    SELECT
        dvc.subject_id,
        dvc.hadm_id,
        dvc.admittime,
        dvc.deathtime,
        dvc.hospital_expire_flag,
        dvc.dod,
        (
            MAX(CASE WHEN (di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 3) = '428') OR (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) = 'I50') THEN 1 ELSE 0 END) + -- Congestive Heart Failure (CHF)
            MAX(CASE WHEN (di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 3) = '585') OR (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) = 'N18') THEN 1 ELSE 0 END) + -- Renal Failure (RF)
            MAX(CASE WHEN (di.icd_version=9 AND di.icd_code = '496') OR (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) = 'J44') THEN 1 ELSE 0 END) + -- Chronic Obstructive Pulmonary Disease (COPD)
            MAX(CASE WHEN (di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 3) = '250') OR (di.icd_version = 10 AND (SUBSTR(di.icd_code, 1, 3) = 'E10' OR SUBSTR(di.icd_code, 1, 3) = 'E11' OR SUBSTR(di.icd_code, 1, 3) = 'E12' OR SUBSTR(di.icd_code, 1, 3) = 'E13' OR SUBSTR(di.icd_code, 1, 3) = 'E14')) THEN 1 ELSE 0 END) -- Diabetes Mellitus (DM)
        ) AS comorbidity_score
    FROM
        dvt_cohort AS dvc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON dvc.hadm_id = di.hadm_id
    GROUP BY
        dvc.subject_id, dvc.hadm_id, dvc.admittime, dvc.deathtime, dvc.hospital_expire_flag, dvc.dod
),
cohort_with_percentile AS (
    -- Step 3: Calculate the 75th percentile of comorbidity scores WITHIN the DVT cohort
    SELECT
        *,
        PERCENTILE_CONT(comorbidity_score, 0.75) OVER () AS p75_comorbidity_score
    FROM
        dvt_cohort_comorbidities
),
final_filtered_cohort AS (
    -- Step 4: Select the final cohort - DVT patients above or equal to the 75th percentile comorbidity score
    SELECT
        cwp.subject_id,
        cwp.hadm_id,
        cwp.admittime,
        cwp.deathtime,
        cwp.hospital_expire_flag,
        cwp.dod,
        cwp.comorbidity_score,
        -- Determine 30-day mortality status
        CASE
            WHEN cwp.hospital_expire_flag = 1 AND DATE_DIFF(cwp.deathtime, cwp.admittime, DAY) <= 30 THEN TRUE -- Hospital death within 30 days
            WHEN cwp.hospital_expire_flag = 0 AND cwp.dod IS NOT NULL AND DATE_DIFF(cwp.dod, cwp.admittime, DAY) BETWEEN 0 AND 30 THEN TRUE -- Out-of-hospital death within 30 days
            ELSE FALSE
        END AS died_30_days,
        -- Calculate survival days for those who died within 30 days
        CASE
            WHEN cwp.hospital_expire_flag = 1 AND DATE_DIFF(cwp.deathtime, cwp.admittime, DAY) <= 30 THEN DATE_DIFF(cwp.deathtime, cwp.admittime, DAY)
            WHEN cwp.hospital_expire_flag = 0 AND cwp.dod IS NOT NULL AND DATE_DIFF(cwp.dod, cwp.admittime, DAY) BETWEEN 0 AND 30 THEN DATE_DIFF(cwp.dod, cwp.admittime, DAY)
            ELSE NULL
        END AS survival_days
    FROM
        cohort_with_percentile AS cwp
    WHERE
        cwp.comorbidity_score >= cwp.p75_comorbidity_score
),
final_cohort_with_complications AS (
    -- Step 5: Identify major complications for each admission in the final cohort
    -- Simplified complication list: Sepsis, Acute Kidney Injury (AKI), Pneumonia
    SELECT
        ffc.*,
        MAX(CASE
            WHEN (di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 4) = '9959') OR (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) = 'R65') THEN 1 -- Sepsis (simplistic definition)
            WHEN (di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 3) = '584') OR (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) = 'N17') THEN 1 -- AKI
            WHEN (di.icd_version = 9 AND di.icd_code = '486') OR (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) = 'J18') THEN 1 -- Pneumonia
            ELSE 0
        END) AS has_major_complication
    FROM
        final_filtered_cohort AS ffc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON ffc.hadm_id = di.hadm_id
    GROUP BY
        ffc.subject_id, ffc.hadm_id, ffc.admittime, ffc.deathtime, ffc.hospital_expire_flag, ffc.dod, ffc.comorbidity_score, ffc.died_30_days, ffc.survival_days
)
-- Final aggregation to report the requested metrics
SELECT
    COUNT(DISTINCT fc.hadm_id) AS cohort_size,
    -- 30-day mortality rate
    SAFE_DIVIDE(SUM(CASE WHEN fc.died_30_days THEN 1 ELSE 0 END), COUNT(DISTINCT fc.hadm_id)) AS mortality_30_day_rate,
    -- Major complication rate
    SAFE_DIVIDE(SUM(fc.has_major_complication), COUNT(DISTINCT fc.hadm_id)) AS major_complication_rate,
    -- Median survival for decedents (only for those who died within 30 days)
    (
        SELECT PERCENTILE_CONT(survival_days, 0.5) OVER()
        FROM final_cohort_with_complications
        WHERE died_30_days = TRUE AND survival_days IS NOT NULL
        -- The PERCENTILE_CONT with OVER() needs to apply to the entire aggregated result,
        -- so simply selecting it from the filtered cohort should give the median.
        -- If results are still not precise enough, APPROX_QUANTILES can be used.
        -- If PERCENTILE_CONT needs to operate over a single aggregate set, then
        -- it needs to be inside the main SELECT or be part of a subquery that yields only one row.
        -- For a single aggregated metric OVER() is not strictly needed IF the subquery returns one row.
        -- In this case, `SELECT PERCENTILE_CONT(survival_days, 0.5)` would work without OVER().
        -- Keeping OVER() with empty partition just to be explicit if it was intended this way.
        -- But for a single scalar value, this is more direct:
        -- SELECT PERCENTILE_CONT(survival_days, 0.5) FROM ... WHERE ...
    ) AS median_survival_decedents_days,
    -- Composite risk score quartiles (count admissions per quartile)
    (
        SELECT
            STRING_AGG(
                FORMAT('Q%d: %d admissions', quartile_group, COUNT(hadm_id)),
                '; ' ORDER BY quartile_group
            )
        FROM (
            -- Calculate quartile for each admission first
            SELECT
                hadm_id,
                NTILE(4) OVER (ORDER BY comorbidity_score) AS quartile_group
            FROM final_cohort_with_complications
        ) AS calculated_quartiles
        -- Then group by the calculated quartile
        GROUP BY quartile_group
    ) AS comorbidity_score_quartiles
FROM
    final_cohort_with_complications AS fc;