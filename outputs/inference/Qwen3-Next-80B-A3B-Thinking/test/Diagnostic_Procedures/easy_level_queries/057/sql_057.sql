SELECT MIN(procedure_count) AS min_procedures
FROM (
    SELECT p.subject_id, COUNT(dip.icd_code) AS procedure_count
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
        ON p.subject_id = pi.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
        ON pi.icd_code = dip.icd_code 
        AND pi.icd_version = dip.icd_version 
        AND dip.long_title LIKE '%cardiac%' 
        AND dip.long_title LIKE '%catheterization%'
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 64 AND 74
    GROUP BY p.subject_id
) AS counts;