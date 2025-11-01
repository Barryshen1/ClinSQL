WITH cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.discharge_location,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 44 AND 54
        AND adm.dischtime IS NOT NULL
        AND icu.hadm_id IS NULL  -- Exclude any ICU stay
        AND adm.discharge_location IN ('HOME', 'HOSPICE', 'DEAD/EXPIRED')
),
discharge_groups AS (
    SELECT 
        CASE 
            WHEN discharge_location = 'HOME' THEN 'home'
            WHEN discharge_location = 'HOSPICE' THEN 'hospice'
            WHEN discharge_location = 'DEAD/EXPIRED' THEN 'death'
        END AS discharge_category,
        los
    FROM cohort
)
SELECT 
    discharge_category,
    COUNT(*) AS n,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
    APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95,
    ROUND(SAFE_DIVIDE(COUNTIF(los <= 7), COUNT(*)) * 100, 2) AS percentile_rank_7day
FROM discharge_groups
GROUP BY discharge_category
ORDER BY discharge_category;