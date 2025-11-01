WITH male_45_55 AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 45 AND 55
),
cabg_counts AS (
    SELECT
        m.subject_id,
        COUNT(d.icd_code) AS cabg_count
    FROM male_45_55 m
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr ON m.subject_id = pr.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON pr.icd_code = d.icd_code 
        AND pr.icd_version = d.icd_version 
        AND LOWER(d.long_title) LIKE '%cabg%'
    GROUP BY m.subject_id
)
SELECT
    PERCENTILE_CONT(cabg_count, 0.25) AS percentile_25
FROM cabg_counts;