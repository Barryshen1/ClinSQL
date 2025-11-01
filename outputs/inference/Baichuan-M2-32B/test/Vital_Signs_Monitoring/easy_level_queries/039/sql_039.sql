WITH patient_icu AS (
    SELECT
        p.subject_id,
        p.gender,
        -- Calculate birth year: anchor_year - anchor_age
        p.anchor_year - p.anchor_age AS birth_year,
        i.hadm_id,
        i.stay_id,
        i.intime,
        -- Calculate age at ICU admission
        EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) AS age_at_icu
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON p.subject_id = i.subject_id
    WHERE p.gender = 'F'
        AND EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) BETWEEN 51 AND 61
),
respiratory_rate_items AS (
    SELECT
        itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE category = 'Vital Signs'
        AND label LIKE '%Respiratory Rate%'
        -- Exclude items that are not numeric or have warnings
        AND param_type = 'Numeric'
),
first_rr_per_stay AS (
    SELECT
        p.subject_id,
        p.stay_id,
        p.age_at_icu,
        ce.charttime,
        ce.valuenum AS respiratory_rate
    FROM patient_icu p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON p.subject_id = ce.subject_id
        AND p.stay_id = ce.stay_id
    INNER JOIN respiratory_rate_items rri
        ON ce.itemid = rri.itemid
    WHERE ce.charttime >= p.intime
        AND ce.charttime <= DATETIME_ADD(p.intime, INTERVAL 6 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.warning IS NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY p.stay_id
        ORDER BY ce.charttime ASC
    ) = 1
)
SELECT
    APPROX_QUANTILES(respiratory_rate, 4)[OFFSET(1)] AS p25_first_rr
FROM first_rr_per_stay;