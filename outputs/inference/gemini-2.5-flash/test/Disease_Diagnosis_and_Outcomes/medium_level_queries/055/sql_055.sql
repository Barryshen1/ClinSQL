WITH cohort_patients AS (
    -- 1. Identify male patients aged 71-81
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 71 AND 81
),
cohort_admissions_with_complications AS (
    -- 1. Filter admissions for 'complications of care' ICD codes
    SELECT DISTINCT
        ca.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        cohort_patients ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON ca.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        -- ICD-10 complications of care
        (di.icd_version = 10 AND di.icd_code LIKE 'T8%')
        -- ICD-9 complications of medical and surgical care
        OR (di.icd_version = 9 AND di.icd_code BETWEEN '996' AND '999')
),
admissions_with_icu_status AS (
    -- 2. Determine ICU status and calculate LOS for each admission
    SELECT
        c.subject_id,
        c.hadm_id,
        c.hospital_expire_flag,
        DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
                WHERE icu.hadm_id = c.hadm_id
            ) THEN 'ICU'
            ELSE 'Non-ICU'
        END AS icu_status
    FROM
        cohort_admissions_with_complications c
),
admissions_with_los_quartile AS (
    -- 3. Calculate LOS Quartiles across the entire cohort
    SELECT
        *,
        NTILE(4) OVER (ORDER BY los_days) AS los_quartile
    FROM
        admissions_with_icu_status
),
mechanical_ventilation_flags AS (
    -- 4. Identify admissions with mechanical ventilation (primarily ICU)
    SELECT DISTINCT
        hadm_id,
        1 AS mech_vent_flag
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE
        itemid IN (
            223848, -- Ventilator Mode (CHARTEVENTS)
            224687, -- Mechanical Ventilator MAS (Mode) (CHARTEVENTS)
            224688, -- Mechanical Ventilator Rate (CHARTEVENTS)
            224689, -- Mechanical Ventilator FiO2 (CHARTEVENTS)
            224690, -- Mechanical Ventilator PEEP (CHARTEVENTS)
            224691, -- Mechanical Ventilator Peak Inspiratory Pressure (CHARTEVENTS)
            223849  -- Ventilator Mode (CHARTEVENTS)
        )
        AND valuenum IS NOT NULL -- ensure a measurement was recorded
),
vasopressor_flags AS (
    -- 4. Identify admissions with vasopressor administration
    SELECT DISTINCT
        hadm_id,
        1 AS vasopressor_flag
    FROM `physionet-data.mimiciv_3_1_icu.inputevents`
    WHERE itemid IN (
        221906, -- Norepinephrine
        221289, -- Dopamine
        221662, -- Epinephrine
        222370  -- Vasopressin
    )
    UNION DISTINCT -- Use UNION DISTINCT to combine and avoid duplicates for same hadm_id
    SELECT DISTINCT
        hadm_id,
        1 AS vasopressor_flag
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE
        (LOWER(drug) LIKE '%norepinephrine%' OR
         LOWER(drug) LIKE '%epinephrine%' OR
         LOWER(drug) LIKE '%dopamine%' OR
         LOWER(drug) LIKE '%vasopressin%')
),
rrt_flags AS (
    -- 4. Identify admissions with Renal Replacement Therapy
    SELECT DISTINCT
        hadm_id,
        1 AS rrt_flag
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE
        (icd_version = 10 AND icd_code LIKE '5A1D%') -- ICD-10-PCS: Extracorporeal Filtration (e.g., Hemodialysis)
        OR
        (icd_version = 9 AND icd_code IN ('39.95', '54.98')) -- ICD-9: Hemodialysis, Peritoneal dialysis
),
admissions_with_all_flags AS (
    -- Combine all flags with the main cohort
    SELECT
        alq.subject_id,
        alq.hadm_id,
        alq.icu_status,
        alq.los_quartile,
        alq.hospital_expire_flag,
        COALESCE(mvf.mech_vent_flag, 0) AS mech_vent_flag,
        COALESCE(vpf.vasopressor_flag, 0) AS vasopressor_flag,
        COALESCE(rrf.rrt_flag, 0) AS rrt_flag
    FROM
        admissions_with_los_quartile alq
    LEFT JOIN
        mechanical_ventilation_flags mvf
        ON alq.hadm_id = mvf.hadm_id
    LEFT JOIN
        vasopressor_flags vpf
        ON alq.hadm_id = vpf.hadm_id
    LEFT JOIN
        rrt_flags rrf
        ON alq.hadm_id = rrf.hadm_id
),
aggregated_results AS (
    -- Group by ICU status and LOS quartile to calculate rates
    SELECT
        icu_status,
        los_quartile,
        COUNT(DISTINCT hadm_id) AS N_Admissions,
        AVG(hospital_expire_flag) * 100 AS In_Hospital_Mortality_Rate,
        AVG(mech_vent_flag) * 100 AS Pct_Mechanical_Ventilation,
        AVG(vasopressor_flag) * 100 AS Pct_Vasopressors,
        AVG(rrt_flag) * 100 AS Pct_RRT
    FROM
        admissions_with_all_flags
    GROUP BY
        icu_status,
        los_quartile
)
-- Final selection and calculation of absolute/relative difference versus Q1
SELECT
    ar.icu_status,
    ar.los_quartile,
    ar.N_Admissions,
    ROUND(ar.In_Hospital_Mortality_Rate, 2) AS In_Hospital_Mortality_Rate,
    ROUND(
        ar.In_Hospital_Mortality_Rate - FIRST_VALUE(ar.In_Hospital_Mortality_Rate) OVER (PARTITION BY ar.icu_status ORDER BY ar.los_quartile), 2
    ) AS Abs_Mortality_vs_Q1,
    ROUND(
      (ar.In_Hospital_Mortality_Rate / FIRST_VALUE(ar.In_Hospital_Mortality_Rate) OVER (PARTITION BY ar.icu_status ORDER BY ar.los_quartile) - 1) * 100, 2
    ) AS Relative_Mortality_vs_Q1,
    ROUND(ar.Pct_Mechanical_Ventilation, 2) AS Pct_Mechanical_Ventilation,
    ROUND(ar.Pct_Vasopressors, 2) AS Pct_Vasopressors,
    ROUND(ar.Pct_RRT, 2) AS Pct_RRT
FROM
    aggregated_results ar
ORDER BY
    ar.icu_status,
    ar.los_quartile;