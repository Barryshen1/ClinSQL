WITH FirstAdmissionsICUStays AS (
    -- Select patients who are female, 50-60 years old.
    -- Identify their first hospital admission and first ICU stay within that admission, along with its LOS.
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        icu.los,
        ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY adm.admittime) AS rn_adm, -- Rank admissions for each patient
        ROW_NUMBER() OVER (PARTITION BY p.subject_id, adm.hadm_id ORDER BY icu.intime) AS rn_icu -- Rank ICU stays for each admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id AND p.subject_id = icu.subject_id
    WHERE
        p.gender = 'F'
        -- Corrected age filter: 50-60 years old as per the clinical question
        AND p.anchor_age BETWEEN 50 AND 60
),
AnticoagulantPatients AS (
    -- Identify subject_id and hadm_id for patients who received an anticoagulant
    -- during their first hospital admission and meet the demographic criteria.
    SELECT DISTINCT
        fa.subject_id,
        fa.hadm_id
    FROM
        FirstAdmissionsICUStays fa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON fa.subject_id = pr.subject_id AND fa.hadm_id = pr.hadm_id
    WHERE
        fa.rn_adm = 1 -- Only consider prescriptions during their first admission
        AND (
            LOWER(pr.drug) LIKE '%warfarin%'
            OR LOWER(pr.drug) LIKE '%heparin%' AND LOWER(pr.drug) NOT LIKE '%flush%' -- Exclude heparin flushes
            OR LOWER(pr.drug) LIKE '%enoxaparin%'
            OR LOWER(pr.drug) LIKE '%rivaroxaban%'
            OR LOWER(pr.drug) LIKE '%dabigatran%'
            OR LOWER(pr.drug) LIKE '%apixaban%'
            OR LOWER(pr.drug) LIKE '%fondaparinux%'
            OR LOWER(pr.drug) LIKE '%edoxaban%'
        )
)
-- Final calculation: Median ICU LOS for the target population
SELECT
    -- Fix: Use APPROX_QUANTILES to calculate the median (50th percentile)
    APPROX_QUANTILES(fa.los, 100)[OFFSET(50)] AS median_icu_los_days
FROM
    FirstAdmissionsICUStays fa
INNER JOIN
    AnticoagulantPatients ap
    ON fa.subject_id = ap.subject_id AND fa.hadm_id = ap.hadm_id
WHERE
    fa.rn_adm = 1 -- Ensure we are considering their first hospital admission
    AND fa.rn_icu = 1; -- Ensure we are considering their first ICU stay within that admission;