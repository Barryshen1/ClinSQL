WITH filtered_admissions AS (
    SELECT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 57 AND 67
)
SELECT MIN(procedure_count) AS min_valve_procedures
FROM (
    SELECT a.hadm_id,
           COUNT(DISTINCT CASE 
               WHEN d.long_title LIKE '%valve repair%' OR d.long_title LIKE '%valve replacement%' 
               THEN p.icd_code 
           END) AS procedure_count
    FROM filtered_admissions a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p 
        ON a.hadm_id = p.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    GROUP BY a.hadm_id
) AS counts;