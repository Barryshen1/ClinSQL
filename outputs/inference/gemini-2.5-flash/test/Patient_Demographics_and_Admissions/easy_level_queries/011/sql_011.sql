WITH PatientDemographics AS (
    -- Select subjects based on gender and anchor_age
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 76 AND 86
),
AntiplateletPrescriptions AS (
    -- Identify distinct antiplatelet drug types prescribed per hospital admission
    SELECT DISTINCT
        pres.subject_id,
        pres.hadm_id,
        CASE
            WHEN LOWER(pres.drug) LIKE '%aspirin%' OR LOWER(pres.drug) LIKE '%asa%' THEN 'Aspirin'
            WHEN LOWER(pres.drug) LIKE '%clopidogrel%' OR LOWER(pres.drug) LIKE '%plavix%' THEN 'P2Y12_inhibitor'
            WHEN LOWER(pres.drug) LIKE '%ticagrelor%' OR LOWER(pres.drug) LIKE '%brilinta%' THEN 'P2Y12_inhibitor'
            WHEN LOWER(pres.drug) LIKE '%prasugrel%' OR LOWER(pres.drug) LIKE '%effient%' THEN 'P2Y12_inhibitor'
            ELSE NULL -- Should not happen if filtered correctly below
        END AS antiplatelet_type
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    WHERE
        (LOWER(pres.drug) LIKE '%aspirin%' OR LOWER(pres.drug) LIKE '%asa%') OR
        (LOWER(pres.drug) LIKE '%clopidogrel%' OR LOWER(pres.drug) LIKE '%plavix%') OR
        (LOWER(pres.drug) LIKE '%ticagrelor%' OR LOWER(pres.drug) LIKE '%brilinta%') OR
        (LOWER(pres.drug) LIKE '%prasugrel%' OR LOWER(pres.drug) LIKE '%effient%')
),
DAPTPatients AS (
    -- Filter for admissions receiving Dual Antiplatelet Therapy (Aspirin + P2Y12 inhibitor)
    SELECT
        ap.subject_id,
        ap.hadm_id
    FROM
        AntiplateletPrescriptions ap
    GROUP BY
        ap.subject_id, ap.hadm_id
    HAVING
        SUM(CASE WHEN ap.antiplatelet_type = 'Aspirin' THEN 1 ELSE 0 END) >= 1
        AND SUM(CASE WHEN ap.antiplatelet_type = 'P2Y12_inhibitor' THEN 1 ELSE 0 END) >= 1
),
FirstICUStay AS (
    -- Get the first ICU stay for each hospital admission
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.los,
        ROW_NUMBER() OVER (PARTITION BY ie.hadm_id ORDER BY ie.intime) as rn
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
)
-- Final selection and aggregation
SELECT
    AVG(fics.los) AS average_icu_los_days
FROM
    PatientDemographics pd
INNER JOIN
    DAPTPatients dapt
    ON pd.subject_id = dapt.subject_id AND pd.hadm_id = dapt.hadm_id
INNER JOIN
    FirstICUStay fics
    ON dapt.subject_id = fics.subject_id AND dapt.hadm_id = fics.hadm_id
WHERE
    fics.rn = 1;