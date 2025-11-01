SELECT
    PERCENTILE_CONT(t.duration_days, 0.75) OVER () - PERCENTILE_CONT(t.duration_days, 0.25) OVER () AS iqr_atorvastatin_duration_days
FROM
    (
        SELECT
            TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
        FROM
            `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.admissions` AS a
            ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` AS pa
            ON p.subject_id = pa.subject_id
        WHERE
            -- 1. Demographic filter: Women aged 75-85 at admission
            pa.gender = 'F'
            AND (pa.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pa.anchor_year)) BETWEEN 75 AND 85
            -- 2. Drug filter: Atorvastatin
            AND LOWER(p.drug) LIKE '%atorvastatin%'
            -- 3. Dosage filter: Single high-intensity (40-80 mg)
            -- Extract the numeric strength in mg, allowing for decimals and optional space before 'mg'
            AND SAFE_CAST(REGEXP_EXTRACT(LOWER(p.prod_strength), r'(\d+(?:\.\d+)?)\s*mg') AS FLOAT64) IS NOT NULL
            AND SAFE_CAST(REGEXP_EXTRACT(LOWER(p.prod_strength), r'(\d+(?:\.\d+)?)\s*mg') AS FLOAT64) BETWEEN 40 AND 80
            -- 4. Ensure valid prescription times and non-negative duration
            AND p.starttime IS NOT NULL
            AND p.stoptime IS NOT NULL
            AND TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) >= 0
    ) AS t
QUALIFY ROW_NUMBER() OVER(ORDER BY 1) = 1
;