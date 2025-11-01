SELECT MIN(procedure_count) AS min_procedures
FROM (
    SELECT p.subject_id, COUNT(pr.hadm_id) AS procedure_count
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr ON p.subject_id = pr.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 64 AND 74
      AND pr.icd_code = '36.01'
      AND pr.icd_version = 9
    GROUP BY p.subject_id
);