WITH eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE anchor_age = 90
      AND gender = 'M'
),
admissions_with_copd AS (
    SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN eligible_patients p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    WHERE d.icd_code LIKE 'J44%' 
      AND d.icd_version = 10
),
creatinine_itemids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE label LIKE '%creatinine%'
      AND fluid = 'Serum'
),
first_24h_creatinine AS (
    SELECT 
        l.hadm_id,
        l.valuenum AS creatinine_value,
        TIMESTAMP_DIFF(l.charttime, a.admittime, HOUR) AS hours_since_admit
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN admissions_with_copd a ON l.hadm_id = a.hadm_id
    JOIN creatinine_itemids c ON l.itemid = c.itemid
    WHERE l.valuenum IS NOT NULL
      AND TIMESTAMP_DIFF(l.charttime, a.admittime, HOUR) BETWEEN 0 AND 24
),
avg_creatinine_per_admission AS (
    SELECT 
        hadm_id,
        AVG(creatinine_value) AS avg_creatinine
    FROM first_24h_creatinine
    GROUP BY hadm_id
)
SELECT 
    STDDEV(avg_creatinine) AS std_dev_avg_creatinine
FROM avg_creatinine_per_admission;