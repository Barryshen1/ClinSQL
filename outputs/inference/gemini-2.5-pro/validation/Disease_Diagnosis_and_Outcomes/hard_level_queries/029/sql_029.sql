WITH
-- 1. Identify the base cohort of female patients aged 82-92 with a pneumonia diagnosis
pneumonia_cohort AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.dod,
        -- Calculate age at admission as a common approximation
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 82 AND 92
        AND a.hadm_id IN ( -- Filter for hospitalizations with a pneumonia diagnosis
            SELECT DISTINCT dx.hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
                ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
            WHERE LOWER(d_dx.long_title) LIKE '%pneumonia%'
        )
),

-- 2a. Get the first lab values for BUN and WBC within 24h of admission for the cohort
first_labs_raw AS (
    SELECT
        le.hadm_id,
        le.itemid,
        le.valuenum,
        ROW_NUMBER() OVER(PARTITION BY le.hadm_id, le.itemid ORDER BY le.charttime) as rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN
        pneumonia_cohort pc ON le.hadm_id = pc.hadm_id
    WHERE
        le.itemid IN (51006, 51301, 51300) -- BUN, WBC
        AND le.valuenum IS NOT NULL
        AND le.charttime BETWEEN pc.admittime AND DATETIME_ADD(pc.admittime, INTERVAL 24 HOUR)
),

-- 2b. Calculate cohort-wide medians of the first lab values for imputation
lab_medians AS (
    SELECT
        APPROX_QUANTILES(CASE WHEN itemid = 51006 THEN valuenum END, 100)[OFFSET(50)] as median_bun,
        APPROX_QUANTILES(CASE WHEN itemid IN (51301, 51300) THEN valuenum END, 100)[OFFSET(50)] as median_wbc
    FROM first_labs_raw
    WHERE rn = 1
),

-- 2c. Pivot lab results and impute missing values to ensure all patients have a score component
first_labs_pivoted AS (
    SELECT
        pc.hadm_id,
        COALESCE(
            MAX(CASE WHEN flr.itemid = 51006 THEN flr.valuenum END),
            (SELECT median_bun FROM lab_medians)
        ) AS first_bun,
        COALESCE(
            MAX(CASE WHEN flr.itemid IN (51301, 51300) THEN flr.valuenum END),
            (SELECT median_wbc FROM lab_medians)
        ) AS first_wbc
    FROM
        pneumonia_cohort pc
    LEFT JOIN
        first_labs_raw flr ON pc.hadm_id = flr.hadm_id AND flr.rn = 1
    GROUP BY
        pc.hadm_id
),

-- 3. Identify in-hospital cardiovascular and neurologic complications (diagnoses with seq_num > 1)
complications AS (
    SELECT
        dx.hadm_id,
        MAX(CASE
            WHEN (dx.icd_version = 9 AND dx.icd_code BETWEEN '390' AND '459')
              OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 1) = 'I')
            THEN 1 ELSE 0
        END) AS has_cardiac_complication,
        MAX(CASE
            WHEN (dx.icd_version = 9 AND (dx.icd_code BETWEEN '320' AND '359' OR dx.icd_code IN ('2930', '78009')))
              OR (dx.icd_version = 10 AND (SUBSTR(dx.icd_code, 1, 1) = 'G' OR dx.icd_code LIKE 'F05%' OR dx.icd_code = 'R410'))
            THEN 1 ELSE 0
        END) AS has_neuro_complication
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    WHERE dx.hadm_id IN (SELECT hadm_id FROM pneumonia_cohort) AND dx.seq_num > 1
    GROUP BY dx.hadm_id
),

-- 4. Combine all features, calculate outcomes and the composite risk score
cohort_features AS (
    SELECT
        pc.hadm_id,
        pc.hospital_expire_flag,
        CASE
            WHEN pc.dod IS NOT NULL AND DATE_DIFF(DATE(pc.dod), DATE(pc.admittime), DAY) BETWEEN 0 AND 30
            THEN 1 ELSE 0
        END AS is_30_day_mortality,
        DATETIME_DIFF(pc.dischtime, pc.admittime, SECOND) / 86400.0 AS los_days,
        COALESCE(c.has_cardiac_complication, 0) AS has_cardiac_complication,
        COALESCE(c.has_neuro_complication, 0) AS has_neuro_complication,
        pc.age_at_admission + flp.first_bun + flp.first_wbc AS composite_risk_score
    FROM
        pneumonia_cohort pc
    INNER JOIN
        first_labs_pivoted flp ON pc.hadm_id = flp.hadm_id
    LEFT JOIN
        complications c ON pc.hadm_id = c.hadm_id
),

-- 5. Stratify the cohort into quintiles based on the risk score
cohort_quintiles AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY composite_risk_score) AS risk_quintile
    FROM
        cohort_features
)

-- 6. Aggregate results by quintile and compute final metrics
SELECT
    risk_quintile,
    COUNT(*) AS num_patients,
    ROUND(AVG(is_30_day_mortality) * 100, 2) AS mortality_rate_30_day_pct,
    ROUND(AVG(has_cardiac_complication) * 100, 2) AS cardiac_complication_rate_pct,
    ROUND(AVG(has_neuro_complication) * 100, 2) AS neuro_complication_rate_pct,
    ROUND(
        CAST(APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END, 100)[OFFSET(50)] AS NUMERIC),
        2
    ) AS median_los_survivors_days
FROM
    cohort_quintiles
GROUP BY
    risk_quintile
ORDER BY
    risk_quintile;