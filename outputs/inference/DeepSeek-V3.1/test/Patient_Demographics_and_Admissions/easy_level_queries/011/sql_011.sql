WITH first_admission AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS admission_rank
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M' 
        AND p.anchor_age BETWEEN 76 AND 86
),
dapt_drugs AS (
    SELECT 
        fa.subject_id,
        fa.hadm_id,
        STRING_AGG(DISTINCT LOWER(pr.drug)) AS drugs_list
    FROM first_admission fa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON fa.hadm_id = pr.hadm_id
    WHERE LOWER(pr.drug) LIKE '%aspirin%' 
        OR LOWER(pr.drug) LIKE '%clopidogrel%' 
        OR LOWER(pr.drug) LIKE '%ticagrelor%' 
        OR LOWER(pr.drug) LIKE '%prasugrel%'
    GROUP BY fa.subject_id, fa.hadm_id
    HAVING 
        (SUM(CASE WHEN LOWER(pr.drug) LIKE '%aspirin%' THEN 1 ELSE 0 END) >= 1)
        AND (SUM(CASE WHEN LOWER(pr.drug) LIKE '%clopidogrel%' THEN 1 ELSE 0 END) >= 1
            OR SUM(CASE WHEN LOWER(pr.drug) LIKE '%ticagrelor%' THEN 1 ELSE 0 END) >= 1
            OR SUM(CASE WHEN LOWER(pr.drug) LIKE '%prasugrel%' THEN 1 ELSE 0 END) >= 1)
),
icu_los AS (
    SELECT 
        fa.subject_id,
        fa.hadm_id,
        COALESCE(SUM(icu.los), 0) AS total_icu_los
    FROM first_admission fa
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON fa.hadm_id = icu.hadm_id
    WHERE fa.admission_rank = 1
    GROUP BY fa.subject_id, fa.hadm_id
)
SELECT 
    ROUND(AVG(il.total_icu_los), 2) AS avg_icu_los_days
FROM first_admission fa
INNER JOIN dapt_drugs dd
    ON fa.hadm_id = dd.hadm_id
INNER JOIN icu_los il
    ON fa.hadm_id = il.hadm_id
WHERE fa.admission_rank = 1;