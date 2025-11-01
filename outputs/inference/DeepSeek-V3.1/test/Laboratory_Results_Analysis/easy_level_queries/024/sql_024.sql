WITH sepsis_admissions AS (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        (icd_version = 9 AND icd_code LIKE '038%') OR
        (icd_version = 9 AND icd_code IN ('99591', '99592')) OR
        (icd_version = 10 AND icd_code LIKE 'A41%') OR
        (icd_version = 10 AND icd_code IN ('R6520', 'R6521'))
),
first_platelet_time AS (
    SELECT 
        lab.subject_id,
        lab.hadm_id,
        MIN(lab.charttime) AS first_charttime
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
    INNER JOIN sepsis_admissions sa 
        ON lab.subject_id = sa.subject_id 
        AND lab.hadm_id = sa.hadm_id
    WHERE lab.itemid = 51265  -- Platelet count
    AND lab.valuenum IS NOT NULL
    GROUP BY lab.subject_id, lab.hadm_id
),
first_platelet_value AS (
    SELECT 
        lab.subject_id,
        lab.hadm_id,
        lab.valuenum AS first_platelet_count
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
    INNER JOIN first_platelet_time fpt
        ON lab.subject_id = fpt.subject_id
        AND lab.hadm_id = fpt.hadm_id
        AND lab.charttime = fpt.first_charttime
    WHERE lab.itemid = 51265
)
SELECT 
    STDDEV(fp.first_platelet_count) AS platelet_sd
FROM first_platelet_value fp
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON fp.subject_id = p.subject_id
WHERE p.gender = 'M';