WITH eligible_admissions AS (
    SELECT
        a.hadm_id,
        a.subject_id,
        a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 41 AND 51
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE
                d.subject_id = a.subject_id
                AND d.hadm_id = a.hadm_id
                AND (d.icd_code LIKE 'R07%' OR d.icd_code LIKE 'I21.%')
        )
),
troponin_measurements AS (
    SELECT
        e.hadm_id,
        e.subject_id,
        e.valuenum,
        e.charttime
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` e
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
        ON e.itemid = d.itemid
    WHERE
        d.label LIKE '%Troponin T%'
        AND d.category = 'Cardiac'
        AND e.valueuom = 'ng/mL'
        AND e.valuenum IS NOT NULL
),
first_troponin_per_admission AS (
    SELECT
        t.hadm_id,
        t.subject_id,
        t.valuenum,
        t.charttime,
        ROW_NUMBER() OVER (
            PARTITION BY t.hadm_id
            ORDER BY t.charttime
        ) AS rn
    FROM troponin_measurements t
    INNER JOIN eligible_admissions e
        ON t.hadm_id = e.hadm_id
        AND t.subject_id = e.subject_id
),
categorized_troponin AS (
    SELECT
        hadm_id,
        valuenum,
        CASE
            WHEN valuenum <= 0.01 THEN 'Normal'
            WHEN valuenum > 0.01 AND valuenum <= 0.03 THEN 'Borderline'
            WHEN valuenum > 0.03 THEN 'Elevated'
        END AS category
    FROM first_troponin_per_admission
    WHERE rn = 1
),
aggregated_stats AS (
    SELECT
        category,
        COUNT(*) AS count,
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage,
        AVG(valuenum) AS mean,
        APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
        APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
        APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75,
        APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr
    FROM categorized_troponin
    GROUP BY category
)
SELECT
    category,
    count,
    percentage,
    mean,
    median,
    p25,
    p75,
    iqr
FROM aggregated_stats
ORDER BY 
    CASE category
        WHEN 'Normal' THEN 1
        WHEN 'Borderline' THEN 2
        WHEN 'Elevated' THEN 3
    END;