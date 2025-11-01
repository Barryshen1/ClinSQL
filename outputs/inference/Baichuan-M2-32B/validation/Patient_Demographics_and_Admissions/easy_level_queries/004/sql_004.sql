WITH first_admissions AS (
    SELECT 
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
aki_diagnoses AS (
    SELECT DISTINCT
        subject_id,
        hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        (icd_version = 10 AND icd_code LIKE 'N17%') OR 
        (icd_version = 9 AND icd_code IN ('584.5','584.6','584.7','584.8','584.9'))
),
patient_info AS (
    SELECT 
        subject_id,
        gender,
        anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
      AND anchor_age BETWEEN 70 AND 80
)
SELECT 
    STDDEV_SAMP(fa.los_days) AS std_los
FROM first_admissions fa
INNER JOIN patient_info pi 
    ON fa.subject_id = pi.subject_id
INNER JOIN aki_diagnoses ad 
    ON fa.hadm_id = ad.hadm_id 
    AND fa.subject_id = ad.subject_id
WHERE fa.rn = 1;