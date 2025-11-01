WITH patient_admissions AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        p.dod,
        p.gender,
        p.anchor_year,
        p.anchor_age,
        -- Compute birth date: anchor_year is integer, so convert to date
        DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR) AS birth_date,
        -- Age at admission
        DATE_DIFF(a.admittime, DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR), YEAR) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
),
filtered_admissions AS (
    SELECT 
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        dod,
        age_at_admission
    FROM patient_admissions
    WHERE gender = 'M'
        AND age_at_admission BETWEEN 68 AND 78
),
ich_admissions AS (
    SELECT 
        f.subject_id,
        f.hadm_id,
        f.admittime,
        f.dischtime,
        f.dod,
        f.age_at_admission
    FROM filtered_admissions f
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON f.subject_id = d.subject_id AND f.hadm_id = d.hadm_id
    WHERE d.icd_code IN ('I60', 'I61', 'I62') 
        AND d.icd_version = 10
),
icu_discharges AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        -- Removed sapsii because it doesn't exist in icustays
        ich.*
    FROM ich_admissions ich
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON ich.subject_id = i.subject_id AND ich.hadm_id = i.hadm_id
    WHERE i.outtime IS NOT NULL
),
complications AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        -- Check for AKI (N17.9) and ARDS (J80.1) in the same admission
        MAX(CASE WHEN d.icd_code = 'N17.9' AND d.icd_version = 10 THEN 1 ELSE 0 END) AS aki_present,
        MAX(CASE WHEN d.icd_code = 'J80.1' AND d.icd_version = 10 THEN 1 ELSE 0 END) AS ards_present
    FROM icu_discharges i
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
    GROUP BY i.subject_id, i.hadm_id
),
cohort_with_complications AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.admittime,
        i.dischtime,
        i.dod,
        i.age_at_admission,
        -- Removed sapsii
        c.aki_present,
        c.ards_present
    FROM icu_discharges i
    INNER JOIN complications c 
        ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
),
ranked_admissions AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM cohort_with_complications
),
first_admissions AS (
    SELECT 
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        dod,
        age_at_admission,
        -- Removed sapsii
        aki_present,
        ards_present
    FROM ranked_admissions
    WHERE rn = 1
),
outcomes AS (
    SELECT 
        subject_id,
        hadm_id,
        -- 30-day mortality: death within 30 days of discharge
        IF(dod IS NOT NULL AND TIMESTAMP(dod) BETWEEN TIMESTAMP(dischtime) AND TIMESTAMP_ADD(TIMESTAMP(dischtime), INTERVAL 30 DAY), 1, 0) AS thirty_day_mortality,
        -- Survival days for decedents (overall, not just 30-day)
        IF(dod IS NOT NULL, DATE_DIFF(CAST(dod AS DATE), CAST(dischtime AS DATE), DAY), NULL) AS survival_days
    FROM first_admissions
),
cohort_summary AS (
    SELECT 
        COUNT(DISTINCT subject_id) AS cohort_size,
        AVG(thirty_day_mortality) AS thirty_day_mortality_rate,
        AVG(aki_present) AS aki_rate,
        AVG(ards_present) AS ards_rate,
        -- Since sapsii is not available, we return an array of three nulls for risk_quantiles
        [NULL, NULL, NULL] AS risk_quantiles,
        -- Compute median survival days using APPROX_QUANTILES
        (SELECT APPROX_QUANTILES(survival_days, 100)[OFFSET(50)] 
         FROM (SELECT survival_days FROM outcomes WHERE survival_days IS NOT NULL)) AS median_survival_days
    FROM outcomes
)
SELECT 
    cohort_size,
    thirty_day_mortality_rate,
    aki_rate,
    ards_rate,
    -- Extract the three nulls from the risk_quantiles array
    risk_quantiles[OFFSET(0)] AS risk_score_25th,
    risk_quantiles[OFFSET(1)] AS risk_score_50th,
    risk_quantiles[OFFSET(2)] AS risk_score_75th,
    median_survival_days
FROM cohort_summary;