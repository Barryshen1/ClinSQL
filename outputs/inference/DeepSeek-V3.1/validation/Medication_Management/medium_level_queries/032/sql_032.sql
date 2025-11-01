WITH cohort AS (
    SELECT 
        p.subject_id, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 51 AND 61
        AND a.hadm_id IN (
            SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE (
                (icd_version = 10 AND icd_code LIKE 'E1%') 
                OR (icd_version = 9 AND icd_code LIKE '250%')
            )
        )
        AND a.hadm_id IN (
            SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE (
                (icd_version = 10 AND icd_code LIKE 'I50.2%') 
                OR (icd_version = 9 AND icd_code LIKE '428%')
            )
        )
),

-- Define insulin types from emar (non-ICU) and inputevents (ICU)
insulin_events AS (
    -- From emar (non-ICU)
    SELECT 
        e.subject_id,
        e.hadm_id,
        e.charttime,
        e.medication,
        CASE 
            WHEN LOWER(e.medication) LIKE '%glargine%' OR LOWER(e.medication) LIKE '%detemir%' OR LOWER(e.medication) LIKE '%NPH%' THEN 'basal'
            WHEN LOWER(e.medication) LIKE '%lispro%' OR LOWER(e.medication) LIKE '%aspart%' OR LOWER(e.medication) LIKE '%regular%' THEN 'bolus'
            WHEN LOWER(e.medication) LIKE '%sliding%' OR LOWER(e.medication) LIKE '%scale%' THEN 'sliding'
            ELSE NULL
        END AS insulin_type
    FROM `physionet-data.mimiciv_3_1_hosp.emar` e
    WHERE LOWER(e.medication) LIKE '%insulin%'

    UNION ALL

    -- From inputevents (ICU)
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.starttime AS charttime,
        d.label AS medication,
        CASE 
            WHEN LOWER(d.label) LIKE '%glargine%' OR LOWER(d.label) LIKE '%detemir%' OR LOWER(d.label) LIKE '%NPH%' THEN 'basal'
            WHEN LOWER(d.label) LIKE '%lispro%' OR LOWER(d.label) LIKE '%aspart%' OR LOWER(d.label) LIKE '%regular%' THEN 'bolus'
            WHEN LOWER(d.label) LIKE '%sliding%' OR LOWER(d.label) LIKE '%scale%' THEN 'sliding'
            ELSE NULL
        END AS insulin_type
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
        ON i.itemid = d.itemid
    WHERE LOWER(d.label) LIKE '%insulin%'
),

-- For each patient and time window, get flags for each insulin type
first_24h AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        MAX(CASE WHEN i.insulin_type = 'basal' THEN 1 ELSE 0 END) AS basal,
        MAX(CASE WHEN i.insulin_type = 'bolus' THEN 1 ELSE 0 END) AS bolus,
        MAX(CASE WHEN i.insulin_type = 'sliding' THEN 1 ELSE 0 END) AS sliding
    FROM cohort c
    LEFT JOIN insulin_events i
        ON c.subject_id = i.subject_id
        AND c.hadm_id = i.hadm_id
        AND i.charttime >= c.admittime
        AND i.charttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
    GROUP BY c.subject_id, c.hadm_id
),

final_12h AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        MAX(CASE WHEN i.insulin_type = 'basal' THEN 1 ELSE 0 END) AS basal,
        MAX(CASE WHEN i.insulin_type = 'bolus' THEN 1 ELSE 0 END) AS bolus,
        MAX(CASE WHEN i.insulin_type = 'sliding' THEN 1 ELSE 0 END) AS sliding
    FROM cohort c
    LEFT JOIN insulin_events i
        ON c.subject_id = i.subject_id
        AND c.hadm_id = i.hadm_id
        AND i.charttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
        AND i.charttime < c.dischtime
    GROUP BY c.subject_id, c.hadm_id
),

-- Combine to get regimen types
first_regimens AS (
    SELECT 
        subject_id,
        hadm_id,
        CASE WHEN basal = 1 AND bolus = 1 THEN 1 ELSE 0 END AS basal_bolus,
        CASE WHEN basal = 1 AND bolus = 0 THEN 1 ELSE 0 END AS basal_only,
        CASE WHEN basal = 0 AND bolus = 1 THEN 1 ELSE 0 END AS bolus_only,
        sliding AS sliding_scale
    FROM first_24h
),

final_regimens AS (
    SELECT 
        subject_id,
        hadm_id,
        CASE WHEN basal = 1 AND bolus = 1 THEN 1 ELSE 0 END AS basal_bolus,
        CASE WHEN basal = 1 AND bolus = 0 THEN 1 ELSE 0 END AS basal_only,
        CASE WHEN basal = 0 AND bolus = 1 THEN 1 ELSE 0 END AS bolus_only,
        sliding AS sliding_scale
    FROM final_12h
),

-- Aggregate counts
first_counts AS (
    SELECT 
        COUNT(*) AS total,
        SUM(basal_bolus) AS basal_bolus_count,
        SUM(basal_only) AS basal_only_count,
        SUM(bolus_only) AS bolus_only_count,
        SUM(sliding_scale) AS sliding_scale_count
    FROM first_regimens
),

final_counts AS (
    SELECT 
        COUNT(*) AS total,
        SUM(basal_bolus) AS basal_bolus_count,
        SUM(basal_only) AS basal_only_count,
        SUM(bolus_only) AS bolus_only_count,
        SUM(sliding_scale) AS sliding_scale_count
    FROM final_regimens
)

-- Calculate percentages and percentage-point change
SELECT 
    'Basal-Bolus' AS regimen,
    ROUND(100.0 * f.basal_bolus_count / f.total, 2) AS first_24h_percent,
    ROUND(100.0 * fn.basal_bolus_count / fn.total, 2) AS final_12h_percent,
    ROUND(100.0 * fn.basal_bolus_count / fn.total - 100.0 * f.basal_bolus_count / f.total, 2) AS percentage_point_change
FROM first_counts f, final_counts fn

UNION ALL

SELECT 
    'Basal' AS regimen,
    ROUND(100.0 * f.basal_only_count / f.total, 2) AS first_24h_percent,
    ROUND(100.0 * fn.basal_only_count / fn.total, 2) AS final_12h_percent,
    ROUND(100.0 * fn.basal_only_count / fn.total - 100.0 * f.basal_only_count / f.total, 2) AS percentage_point_change
FROM first_counts f, final_counts fn

UNION ALL

SELECT 
    'Bolus' AS regimen,
    ROUND(100.0 * f.bolus_only_count / f.total, 2) AS first_24h_percent,
    ROUND(100.0 * fn.bolus_only_count / fn.total, 2) AS final_12h_percent,
    ROUND(100.0 * fn.bolus_only_count / fn.total - 100.0 * f.bolus_only_count / f.total, 2) AS percentage_point_change
FROM first_counts f, final_counts fn

UNION ALL

SELECT 
    'Sliding-scale' AS regimen,
    ROUND(100.0 * f.sliding_scale_count / f.total, 2) AS first_24h_percent,
    ROUND(100.0 * fn.sliding_scale_count / fn.total, 2) AS final_12h_percent,
    ROUND(100.0 * fn.sliding_scale_count / fn.total - 100.0 * f.sliding_scale_count / f.total, 2) AS percentage_point_change
FROM first_counts f, final_counts fn;