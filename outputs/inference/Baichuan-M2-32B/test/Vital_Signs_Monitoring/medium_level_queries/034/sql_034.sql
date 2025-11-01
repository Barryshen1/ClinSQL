WITH diastolic_bp_itemids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE category = 'Vital Signs' AND label LIKE '%Diastolic%'
),
ventilation_itemids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE label LIKE '%CPAP%' OR label LIKE '%BiPAP%'
),
eligible_icu_stays AS (
    SELECT 
        i.stay_id,
        i.subject_id,
        i.hadm_id,
        i.intime,
        i.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 37 AND 47
        AND i.intime IS NOT NULL
        AND i.outtime IS NOT NULL
),
ventilation_stays AS (
    SELECT DISTINCT
        e.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` e
    INNER JOIN ventilation_itemids v
        ON e.itemid = v.itemid
    INNER JOIN eligible_icu_stays s
        ON e.stay_id = s.stay_id
        AND e.charttime BETWEEN s.intime AND s.outtime
),
diastolic_bp_per_stay AS (
    SELECT
        s.stay_id,
        MAX(e.valuenum) AS max_dbp
    FROM eligible_icu_stays s
    INNER JOIN ventilation_stays v
        ON s.stay_id = v.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` e
        ON s.stay_id = e.stay_id
    INNER JOIN diastolic_bp_itemids d
        ON e.itemid = d.itemid
    WHERE e.charttime BETWEEN s.intime AND s.outtime
        AND e.valuenum IS NOT NULL
    GROUP BY s.stay_id
)
SELECT
    APPROX_QUANTILES(max_dbp, 100)[OFFSET(25)] AS p25_max_dbp
FROM diastolic_bp_per_stay;