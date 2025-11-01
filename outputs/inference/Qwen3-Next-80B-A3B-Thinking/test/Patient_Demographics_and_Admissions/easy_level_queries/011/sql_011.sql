WITH first_admissions AS (
    SELECT subject_id, hadm_id
    FROM (
        SELECT subject_id, hadm_id,
               ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
        FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    )
    WHERE rn = 1
),
male_76_86 AS (
    SELECT fa.subject_id, fa.hadm_id
    FROM first_admissions fa
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON fa.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 76 AND 86
),
dapt_patients AS (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    GROUP BY hadm_id
    HAVING MAX(CASE WHEN LOWER(drug) LIKE '%aspirin%' THEN 1 ELSE 0 END) = 1
        AND MAX(CASE WHEN LOWER(drug) LIKE '%clopidogrel%' THEN 1 ELSE 0 END) = 1
),
icu_los AS (
    SELECT hadm_id, SUM(los) AS total_los
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY hadm_id
)
SELECT AVG(COALESCE(i.total_los, 0)) AS avg_icu_los
FROM male_76_86 m
JOIN dapt_patients d ON m.hadm_id = d.hadm_id
LEFT JOIN icu_los i ON m.hadm_id = i.hadm_id;