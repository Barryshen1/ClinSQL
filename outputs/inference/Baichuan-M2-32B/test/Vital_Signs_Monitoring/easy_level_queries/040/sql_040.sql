WITH patients_with_age AS (
    SELECT 
        subject_id,
        gender,
        anchor_year,
        anchor_age,
        anchor_year - anchor_age AS birth_year
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
),
icu_admissions AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,  -- Added to fix the error
        EXTRACT(YEAR FROM i.intime) - p.birth_year AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN patients_with_age p ON i.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND EXTRACT(YEAR FROM i.intime) - p.birth_year BETWEEN 55 AND 65
),
map_itemids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE (label LIKE '%Mean Arterial Pressure%' OR label LIKE '%MAP%')
      AND unitname = 'mmHg'
),
first_map_per_stay AS (
    SELECT 
        i.stay_id,
        ce.valuenum AS first_map
    FROM icu_admissions i
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON i.subject_id = ce.subject_id
        AND i.hadm_id = ce.hadm_id
        AND i.stay_id = ce.stay_id
    INNER JOIN map_itemids m ON ce.itemid = m.itemid
    WHERE ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN i.intime AND i.outtime  -- Now uses the added outtime
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY i.stay_id 
        ORDER BY ce.charttime
    ) = 1
)
SELECT 
    STDDEV_SAMP(first_map) AS sd_first_map
FROM first_map_per_stay;