WITH cohort AS (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 64 AND 74
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
            ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
          WHERE d.hadm_id = a.hadm_id
            AND LOWER(di.long_title) LIKE '%diabetes%'
      )
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
            ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
          WHERE d.hadm_id = a.hadm_id
            AND LOWER(di.long_title) LIKE '%acute%'
            AND LOWER(di.long_title) LIKE '%heart failure%'
      )
),
total_patients AS (
    SELECT COUNT(*) AS total
    FROM cohort
),
classes AS (
    SELECT 'insulin' AS antidiabetic_class UNION ALL
    SELECT 'metformin' UNION ALL
    SELECT 'sulfonylureas' UNION ALL
    SELECT 'DPP-4' UNION ALL
    SELECT 'SGLT2' UNION ALL
    SELECT 'GLP-1' UNION ALL
    SELECT 'TZDs'
),
prescriptions_with_class AS (
    SELECT *
    FROM (
        SELECT
            p.subject_id,
            p.hadm_id,
            c.admittime,
            c.dischtime,
            p.starttime,
            CASE
                WHEN p.drug LIKE '%insulin%' THEN 'insulin'
                WHEN p.drug LIKE '%metformin%' THEN 'metformin'
                WHEN p.drug LIKE '%glipizide%' OR p.drug LIKE '%glyburide%' OR p.drug LIKE '%gliclazide%' THEN 'sulfonylureas'
                WHEN p.drug LIKE '%sitagliptin%' OR p.drug LIKE '%saxagliptin%' OR p.drug LIKE '%linagliptin%' OR p.drug LIKE '%alogliptin%' THEN 'DPP-4'
                WHEN p.drug LIKE '%empagliflozin%' OR p.drug LIKE '%canagliflozin%' OR p.drug LIKE '%dapagliflozin%' THEN 'SGLT2'
                WHEN p.drug LIKE '%liraglutide%' OR p.drug LIKE '%semaglutide%' OR p.drug LIKE '%exenatide%' OR p.drug LIKE '%dulaglutide%' THEN 'GLP-1'
                WHEN p.drug LIKE '%pioglitazone%' OR p.drug LIKE '%rosiglitazone%' THEN 'TZDs'
                ELSE NULL
            END AS antidiabetic_class
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        JOIN cohort c ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
    )
    WHERE antidiabetic_class IS NOT NULL
),
first_12h AS (
    SELECT
        antidiabetic_class,
        COUNT(DISTINCT subject_id) AS count_first_12h
    FROM prescriptions_with_class
    WHERE starttime BETWEEN admittime AND admittime + INTERVAL '12' HOUR
    GROUP BY antidiabetic_class
),
final_48h AS (
    SELECT
        antidiabetic_class,
        COUNT(DISTINCT subject_id) AS count_final_48h
    FROM prescriptions_with_class
    WHERE starttime BETWEEN dischtime - INTERVAL '48' HOUR AND dischtime
    GROUP BY antidiabetic_class
)
SELECT
    c.antidiabetic_class,
    ROUND(COALESCE(f.count_first_12h, 0) * 100.0 / NULLIF(t.total, 0), 2) AS first_12h_percentage,
    ROUND(COALESCE(final.count_final_48h, 0) * 100.0 / NULLIF(t.total, 0), 2) AS final_48h_percentage
FROM classes c
CROSS JOIN total_patients t
LEFT JOIN first_12h f ON c.antidiabetic_class = f.antidiabetic_class
LEFT JOIN final_48h final ON c.antidiabetic_class = final.antidiabetic_class;