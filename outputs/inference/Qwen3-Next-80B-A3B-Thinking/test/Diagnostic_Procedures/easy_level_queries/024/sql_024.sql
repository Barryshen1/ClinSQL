WITH target_admissions AS (
    SELECT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 58 AND 68
),
procedures_count AS (
    SELECT ta.hadm_id, 
           COUNT(DISTINCT CASE 
               WHEN d.long_title LIKE '%angiography%' 
                    OR d.long_title LIKE '%PCI%' 
                    OR d.long_title LIKE '%percutaneous coronary intervention%' 
                    OR d.long_title LIKE '%cardiac catheterization%' 
               THEN p.icd_code 
           END) AS count_procedures
    FROM target_admissions ta
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p 
        ON ta.hadm_id = p.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    GROUP BY ta.hadm_id
)
SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY count_procedures) AS percentile_75
FROM procedures_count;