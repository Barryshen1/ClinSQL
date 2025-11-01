WITH first_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
filtered_admissions AS (
    SELECT 
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM first_admissions a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    WHERE a.rn = 1
        AND p.gender = 'F'
        AND p.anchor_age BETWEEN 70 AND 80
        AND d.icd_code LIKE 'N17%'
)
SELECT STDDEV(los) AS los_stddev
FROM filtered_admissions;