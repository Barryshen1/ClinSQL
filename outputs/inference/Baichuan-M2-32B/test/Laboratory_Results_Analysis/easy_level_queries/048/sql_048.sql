WITH patient_admissions AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        TIMESTAMP_DIFF(a.admittime, TIMESTAMP(p.anchor_year, 1, 1), YEAR) + p.anchor_age AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE 
        p.gender = 'F' 
        AND TIMESTAMP_DIFF(a.admittime, TIMESTAMP(p.anchor_year, 1, 1), YEAR) + p.anchor_age BETWEEN 55 AND 57
),
admissions_with_copd AS (
    SELECT 
        pa.subject_id,
        pa.hadm_id,
        pa.admittime,
        pa.age_at_admission
    FROM patient_admissions pa
    WHERE EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE pa.hadm_id = d.hadm_id
          AND (
            (d.icd_version = 10 AND d.icd_code LIKE 'J44%')
            OR (d.icd_version = 9 AND d.icd_code BETWEEN '490' AND '496' AND d.icd_code NOT LIKE '493%')
          )
    )
),
creatinine_items AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE label = 'Creatinine'
      AND category = 'Chemistry'
),
creatinine_labs AS (
    SELECT 
        a.hadm_id,
        le.valuenum AS creatinine_value
    FROM admissions_with_copd a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON a.hadm_id = le.hadm_id
    INNER JOIN creatinine_items ci
        ON le.itemid = ci.itemid
    WHERE le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
      AND le.valuenum IS NOT NULL
),
admission_avg_creatinine AS (
    SELECT 
        hadm_id,
        AVG(creatinine_value) AS avg_creatinine
    FROM creatinine_labs
    GROUP BY hadm_id
)
SELECT 
    PERCENTILE_CONT(0.75) OVER (ORDER BY avg_creatinine) AS p75_avg_creatinine
FROM admission_avg_creatinine
LIMIT 1;