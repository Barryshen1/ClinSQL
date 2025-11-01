WITH neutropenia_hadm AS (
    -- Identify admissions with a diagnosis of neutropenia
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND icd_code LIKE 'D70%') OR -- ICD-10 codes for neutropenia
        (icd_version = 9 AND icd_code LIKE '2880%')    -- ICD-9 codes for neutropenia
),
fever_hadm AS (
    -- Identify admissions with a diagnosis of fever
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND icd_code LIKE 'R50%') OR  -- ICD-10 codes for fever
        (icd_version = 9 AND icd_code LIKE '7806%')     -- ICD-9 codes for fever
),
neutropenic_fever_cohort AS (
    -- Select the target patient cohort: female, aged 40-50, with both neutropenia and fever diagnoses
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    INNER JOIN neutropenia_hadm nh ON ad.hadm_id = nh.hadm_id
    INNER JOIN fever_hadm fh ON ad.hadm_id = fh.hadm_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 40 AND 50
),
med_complexity AS (
    -- Calculate medication complexity score (distinct drugs) in the first 48 hours for each admission
    SELECT
        nf.hadm_id,
        COUNT(DISTINCT p.drug) AS medication_complexity_score
    FROM neutropenic_fever_cohort nf
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON nf.subject_id = p.subject_id AND nf.hadm_id = p.hadm_id
    WHERE
        p.starttime BETWEEN nf.admittime AND DATETIME_ADD(nf.admittime, INTERVAL 48 HOUR)
    GROUP BY nf.hadm_id
),
readmissions_flag AS (
    -- Determine 30-day readmission status for each admission in the cohort
    SELECT
        nf.subject_id,
        nf.hadm_id,
        MAX(CASE WHEN ad2.admittime IS NOT NULL THEN 1 ELSE 0 END) AS readmission_30_day_flag
    FROM neutropenic_fever_cohort nf
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad2
        ON nf.subject_id = ad2.subject_id
        AND ad2.admittime > nf.dischtime -- Next admission must be strictly after previous discharge
        AND DATETIME_DIFF(ad2.admittime, nf.dischtime, DAY) <= 30
    GROUP BY nf.subject_id, nf.hadm_id
),
cohort_final_metrics AS (
    -- Combine all relevant metrics for each admission in the cohort
    SELECT
        nf.subject_id,
        nf.hadm_id,
        COALESCE(mc.medication_complexity_score, 0) AS medication_complexity_score, -- Default to 0 if no prescriptions found
        DATETIME_DIFF(nf.dischtime, nf.admittime, HOUR) / 24.0 AS los_days, -- Length of stay in days
        nf.hospital_expire_flag,
        COALESCE(rf.readmission_30_day_flag, 0) AS readmission_30_day_flag
    FROM neutropenic_fever_cohort nf
    LEFT JOIN med_complexity mc
        ON nf.hadm_id = mc.hadm_id
    LEFT JOIN readmissions_flag rf
        ON nf.hadm_id = rf.hadm_id
),
cohort_with_quartiles AS (
    -- Assign medication complexity quartiles
    SELECT
        *,
        NTILE(4) OVER (ORDER BY medication_complexity_score ASC) AS medication_complexity_quartile
    FROM cohort_final_metrics
)
-- Final aggregation to report metrics per quartile
SELECT
    medication_complexity_quartile,
    COUNT(DISTINCT hadm_id) AS patient_count,
    ROUND(AVG(medication_complexity_score), 2) AS mean_med_complexity_score,
    MIN(medication_complexity_score) AS min_med_complexity_score,
    MAX(medication_complexity_score) AS max_med_complexity_score,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(hadm_id), 2) AS mortality_percentage,
    ROUND(SUM(readmission_30_day_flag) * 100.0 / COUNT(hadm_id), 2) AS readmission_30_day_percentage
FROM cohort_with_quartiles
GROUP BY
    medication_complexity_quartile
ORDER BY
    medication_complexity_quartile;