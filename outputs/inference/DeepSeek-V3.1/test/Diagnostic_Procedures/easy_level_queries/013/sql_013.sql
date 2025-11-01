WITH valve_procedures AS (
    SELECT p.subject_id, p.hadm_id, p.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE d.long_title LIKE '%valve%' 
        AND (d.long_title LIKE '%repair%' OR d.long_title LIKE '%replacement%')
),
eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 57 AND 67
),
eligible_admissions AS (
    SELECT a.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN eligible_patients e ON a.subject_id = e.subject_id
),
valve_counts AS (
    SELECT v.hadm_id, COUNT(DISTINCT v.icd_code) AS num_valve_procedures
    FROM valve_procedures v
    INNER JOIN eligible_admissions e ON v.hadm_id = e.hadm_id
    GROUP BY v.hadm_id
)
SELECT MIN(num_valve_procedures) AS min_valve_procedures
FROM valve_counts;