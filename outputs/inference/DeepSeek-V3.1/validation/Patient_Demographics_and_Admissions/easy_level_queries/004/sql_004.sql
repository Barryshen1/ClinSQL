WITH first_admissions AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 70 AND 80
        AND a.admittime = (
            SELECT MIN(a2.admittime)
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
            WHERE a2.subject_id = p.subject_id
        )
),
aki_patients AS (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        (icd_version = 10 AND icd_code LIKE 'N17%') OR
        (icd_version = 9 AND icd_code LIKE '584%')
)
SELECT 
    STDDEV(fa.los_days) AS sd_length_of_stay_days
FROM first_admissions fa
INNER JOIN aki_patients ak
    ON fa.subject_id = ak.subject_id AND fa.hadm_id = ak.hadm_id;