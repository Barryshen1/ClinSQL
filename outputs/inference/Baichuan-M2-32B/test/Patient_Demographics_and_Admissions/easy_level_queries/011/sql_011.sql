WITH eligible_patients AS (
    SELECT
        p.subject_id,
        p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 76 AND 86
),
first_admissions AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN eligible_patients ep ON a.subject_id = ep.subject_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),
dapt_drugs AS (
    SELECT DISTINCT
        subject_id,
        hadm_id,
        drug,
        starttime,  -- Added to fix error
        stoptime    -- Added to fix error
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE drug IN (
        'aspirin', 'clopidogrel', 'ticagrelor', 'prasugrel', 'dipyridamole', 
        'cilostazol', 'ticlopidine'
    )
),
dapt_status AS (
    SELECT
        fa.subject_id,
        fa.hadm_id,
        COUNT(DISTINCT dd.drug) AS num_antiplatelet_drugs
    FROM first_admissions fa
    LEFT JOIN dapt_drugs dd 
        ON fa.subject_id = dd.subject_id 
        AND fa.hadm_id = dd.hadm_id
        -- Ensure the prescription overlaps with the admission
        AND dd.starttime <= fa.dischtime
        AND (dd.stoptime >= fa.admittime OR dd.stoptime IS NULL)
    GROUP BY fa.subject_id, fa.hadm_id
    HAVING num_antiplatelet_drugs >= 2
),
first_icu_stays AS (
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        -- Convert LOS from hours to days
        icu.los / 24.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN first_admissions fa 
        ON icu.subject_id = fa.subject_id 
        AND icu.hadm_id = fa.hadm_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY icu.subject_id, icu.hadm_id ORDER BY icu.intime) = 1
)
SELECT
    AVG(fis.los_days) AS avg_icu_los_days
FROM dapt_status ds
JOIN first_icu_stays fis 
    ON ds.subject_id = fis.subject_id 
    AND ds.hadm_id = fis.hadm_id;