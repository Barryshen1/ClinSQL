WITH map_itemid AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE LOWER(label) = 'map'
),
filtered_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
      AND anchor_age BETWEEN 41 AND 51
),
icu_map_data AS (
    SELECT
        ce.subject_id,
        CASE
            WHEN ce.valuenum < 65 THEN '<65'
            WHEN ce.valuenum >= 65 AND ce.valuenum < 75 THEN '65-74'
            WHEN ce.valuenum >= 75 AND ce.valuenum < 85 THEN '75-84'
            WHEN ce.valuenum >= 85 THEN '>=85'
            ELSE NULL
        END AS map_category
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN map_itemid mi ON ce.itemid = mi.itemid
    JOIN filtered_patients fp ON ce.subject_id = fp.subject_id
    WHERE ce.valuenum IS NOT NULL
      AND ce.valuenum > 0
),
unique_patient_categories AS (
    SELECT DISTINCT subject_id, map_category
    FROM icu_map_data
    WHERE map_category IS NOT NULL
),
stroke_patients AS (
    SELECT DISTINCT di.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
        ON di.icd_code = did.icd_code
        AND di.icd_version = did.icd_version
    WHERE (
        (di.icd_version = 9 AND di.icd_code BETWEEN '430' AND '438')
        OR
        (di.icd_version = 10 AND di.icd_code LIKE 'I6%')
    )
)
SELECT
    upc.map_category,
    COUNT(DISTINCT upc.subject_id) AS patient_count,
    SUM(CASE WHEN sp.subject_id IS NOT NULL THEN 1 ELSE 0 END) AS stroke_count,
    ROUND(
        SUM(CASE WHEN sp.subject_id IS NOT NULL THEN 1 ELSE 0 END) * 100.0 /
        COUNT(DISTINCT upc.subject_id),
        2
    ) AS stroke_rate_percent
FROM unique_patient_categories upc
LEFT JOIN stroke_patients sp ON upc.subject_id = sp.subject_id
GROUP BY upc.map_category
ORDER BY
    CASE upc.map_category
        WHEN '<65' THEN 1
        WHEN '65-74' THEN 2
        WHEN '75-84' THEN 3
        WHEN '>=85' THEN 4
    END;