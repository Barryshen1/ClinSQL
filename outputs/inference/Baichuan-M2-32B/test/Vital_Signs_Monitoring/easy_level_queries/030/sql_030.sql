WITH icu_stays_with_age AS (
    SELECT 
        i.stay_id,
        i.subject_id,
        i.hadm_id,
        i.intime,
        p.gender,
        -- Compute age at ICU admission: anchor_age + (year of intime - anchor_year)
        p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_admission
    FROM 
        `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN 
        `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON i.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 38 AND 48
),
first_hr_per_stay AS (
    SELECT 
        s.stay_id,
        s.subject_id,
        s.intime,
        ce.valuenum AS first_hr_value
    FROM 
        icu_stays_with_age s
    INNER JOIN 
        `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON s.subject_id = ce.subject_id 
        AND s.hadm_id = ce.hadm_id 
        AND s.stay_id = ce.stay_id
    WHERE 
        ce.itemid = 220045  -- Heart Rate
        AND ce.valuenum IS NOT NULL  -- Ensure we have a numeric value
    QUALIFY ROW_NUMBER() OVER (PARTITION BY s.stay_id ORDER BY ce.charttime ASC) = 1
)
SELECT 
    MIN(first_hr_value) AS min_first_hr
FROM 
    first_hr_per_stay;