WITH septic_shock_cohort AS (
    SELECT DISTINCT d.subject_id, d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON d.subject_id = p.subject_id
    WHERE d.icd_code = 'R65.21' 
        AND d.icd_version = 10
        AND p.gender = 'F'
        AND p.anchor_age BETWEEN 89 AND 99
),
control_cohort AS (
    SELECT DISTINCT p.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 89 AND 99
        AND a.hadm_id NOT IN (SELECT hadm_id FROM septic_shock_cohort)
),
shock_index_data AS (
    WITH hr_events AS (
        SELECT 
            c.hadm_id,
            ce.charttime,
            ce.valuenum AS hr
        FROM septic_shock_cohort c
        INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
            ON c.hadm_id = i.hadm_id
        INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
            ON i.stay_id = ce.stay_id
        WHERE ce.itemid = 220045  -- Heart rate
            AND ce.valuenum IS NOT NULL
    ),
    sbp_events AS (
        SELECT 
            c.hadm_id,
            ce.charttime,
            ce.valuenum AS sbp
        FROM septic_shock_cohort c
        INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
            ON c.hadm_id = i.hadm_id
        INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
            ON i.stay_id = ce.stay_id
        WHERE ce.itemid = 220179  -- Systolic BP
            AND ce.valuenum IS NOT NULL
    ),
    combined AS (
        SELECT
            hr.hadm_id,
            hr.hr,
            sbp.sbp,
            ABS(TIMESTAMP_DIFF(hr.charttime, sbp.charttime, MINUTE)) AS time_diff
        FROM hr_events hr
        LEFT JOIN sbp_events sbp
            ON hr.hadm_id = sbp.hadm_id
            AND ABS(TIMESTAMP_DIFF(hr.charttime, sbp.charttime, MINUTE)) <= 60
        QUALIFY ROW_NUMBER() OVER (PARTITION BY hr.hadm_id, hr.charttime ORDER BY ABS(TIMESTAMP_DIFF(hr.charttime, sbp.charttime, MINUTE))) = 1
    )
    SELECT 
        hadm_id,
        MAX(hr / NULLIF(sbp, 0)) AS shock_index
    FROM combined
    GROUP BY hadm_id
),
creatinine_abnormal_septic AS (
    SELECT 
        c.hadm_id,
        MAX(CASE WHEN l.flag = 'abnormal' OR l.valuenum > l.ref_range_upper THEN 1 ELSE 0 END) AS abnormal_creatinine
    FROM septic_shock_cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON c.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON c.hadm_id = l.hadm_id
        AND l.itemid = 50912  -- Creatinine
        AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
    WHERE l.valuenum IS NOT NULL
    GROUP BY c.hadm_id
),
creatinine_abnormal_control AS (
    SELECT 
        c.hadm_id,
        MAX(CASE WHEN l.flag = 'abnormal' OR l.valuenum > l.ref_range_upper THEN 1 ELSE 0 END) AS abnormal_creatinine
    FROM control_cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON c.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON c.hadm_id = l.hadm_id
        AND l.itemid = 50912  -- Creatinine
        AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
    WHERE l.valuenum IS NOT NULL
    GROUP BY c.hadm_id
),
los_mortality AS (
    SELECT
        c.hadm_id,
        DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
        a.hospital_expire_flag
    FROM septic_shock_cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON c.hadm_id = a.hadm_id
)
SELECT
    (SELECT APPROX_QUANTILES(shock_index, 4) FROM shock_index_data) AS si_quartiles,
    COUNT(*) AS septic_count,
    SUM(abnormal_creatinine) AS septic_abnormal,
    ROUND(SUM(abnormal_creatinine) / COUNT(*) * 100, 2) AS septic_pct,
    (SELECT COUNT(*) FROM control_cohort) AS control_count,
    (SELECT SUM(abnormal_creatinine) FROM creatinine_abnormal_control) AS control_abnormal,
    (SELECT ROUND(SUM(abnormal_creatinine) / COUNT(*) * 100, 2) FROM creatinine_abnormal_control) AS control_pct,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
    ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 2) AS mortality_pct
FROM los_mortality
LEFT JOIN creatinine_abnormal_septic USING (hadm_id);