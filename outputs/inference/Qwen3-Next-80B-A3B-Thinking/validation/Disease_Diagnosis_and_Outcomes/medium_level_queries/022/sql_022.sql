WITH sepsis_patients AS (
    SELECT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE (icd_version = 9 AND icd_code IN ('038.9', '995.91', '995.92'))
       OR (icd_version = 10 AND icd_code IN ('A41.9', 'A41.01', 'A41.02', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.8', 'A41.9'))
),
septic_shock_patients AS (
    SELECT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE (icd_version = 9 AND icd_code = '785.52')
       OR (icd_version = 10 AND icd_code = 'R65.21')
),
sepsis_no_shock AS (
    SELECT s.subject_id, s.hadm_id
    FROM sepsis_patients s
    LEFT JOIN septic_shock_patients ss
        ON s.subject_id = ss.subject_id AND s.hadm_id = ss.hadm_id
    WHERE ss.subject_id IS NULL
),
patients_filtered AS (
    SELECT subject_id, anchor_age, gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
      AND anchor_age BETWEEN 50 AND 60
),
admissions_filtered AS (
    SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN sepsis_no_shock s ON a.hadm_id = s.hadm_id
    JOIN patients_filtered p ON a.subject_id = p.subject_id
),
icu_day1_flag AS (
    SELECT a.hadm_id,
           MAX(CASE WHEN i.intime >= a.admittime AND i.intime < a.admittime + INTERVAL '24' HOUR THEN 1 ELSE 0 END) AS icu_day1
    FROM admissions_filtered a
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
    GROUP BY a.hadm_id
),
los_calc AS (
    SELECT 
        a.hadm_id,
        a.hospital_expire_flag,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
        i.icu_day1
    FROM admissions_filtered a
    JOIN icu_day1_flag i ON a.hadm_id = i.hadm_id
)
SELECT 
    CASE WHEN los <= 7 THEN 'LOS <=7' ELSE 'LOS >7' END AS los_group,
    CASE WHEN icu_day1 = 1 THEN 'ICU Day 1' ELSE 'No ICU Day 1' END AS icu_status,
    ROUND(SUM(CAST(hospital_expire_flag AS INT64)) * 100.0 / COUNT(*), 2) AS mortality_rate,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_los
FROM los_calc
GROUP BY los_group, icu_status;