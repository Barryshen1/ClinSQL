WITH stroke_admissions AS (
    SELECT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE seq_num = 1
      AND (
          -- ICD-9 codes for ischemic stroke (with infarction) and 436
          (icd_version = 9 AND icd_code IN ('43301','43311','43321','43331','43381','43391','43401','43411','43491','436'))
          OR
          -- ICD-10 codes: all cerebral infarction (I63)
          (icd_version = 10 AND icd_code LIKE 'I63%')
      )
),
patient_admissions AS (
    SELECT 
        p.subject_id, 
        a.hadm_id,
        a.admittime,
        a.dischtime,
        -- Compute age at admission: anchor_age + (admission year - anchor_year)
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
)
SELECT 
    APPROX_QUANTILES(
        DATETIME_DIFF(pa.dischtime, pa.admittime, HOUR) / 24.0, 
        100
    )[OFFSET(25)] AS percentile_25_los
FROM patient_admissions pa
INNER JOIN stroke_admissions s
    ON pa.subject_id = s.subject_id AND pa.hadm_id = s.hadm_id
WHERE pa.age_at_admission BETWEEN 50 AND 60;