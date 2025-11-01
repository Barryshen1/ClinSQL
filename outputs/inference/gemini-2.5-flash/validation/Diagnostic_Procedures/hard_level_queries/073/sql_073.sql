WITH ranked_icu_stays AS (
    -- Pre-calculate row number for ICU stays to identify the first one
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) as rn
    FROM
        `physionet-data.mimiciv_3_1_icu`.icustays icu
),
cohort_first_icu_stays AS (
    -- Step 1: Identify eligible patients and their first ICU stay,
    -- filtering by age, gender, and hepatic failure diagnosis.
    SELECT
        p.subject_id,
        ad.hadm_id,
        ris.stay_id, -- Use stay_id from ranked_icu_stays
        ris.intime,
        ris.outtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp`.patients p
    JOIN
        `physionet-data.mimiciv_3_1_hosp`.admissions ad
        ON p.subject_id = ad.subject_id
    JOIN
        ranked_icu_stays ris -- Join with the CTE containing ranked ICU stays
        ON ad.hadm_id = ris.hadm_id
    WHERE
        ris.rn = 1 -- Filter for the first ICU stay here, after ROW_NUMBER is calculated
        AND p.gender = 'M'
        AND p.anchor_age = 90 -- Patients >= 90 years old are grouped as 90 in MIMIC-IV
        -- Check for hepatic failure diagnosis during the admission
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd dicd
            WHERE
                dicd.subject_id = ad.subject_id
                AND dicd.hadm_id = ad.hadm_id
                AND (
                    (dicd.icd_version = 9 AND (dicd.icd_code LIKE '570%' OR dicd.icd_code LIKE '5722%')) -- ICD-9 codes for hepatic failure (e.g., 570, 572.2)
                    OR (dicd.icd_version = 10 AND dicd.icd_code LIKE 'K72%') -- ICD-10 codes for hepatic failure (e.g., K72)
                )
        )
),
patient_procedure_counts AS (
    -- Step 2: Count distinct diagnostic procedures within the initial 72 hours of ICU stay,
    -- and calculate LOS.
    SELECT
        cfis.subject_id,
        cfis.hadm_id,
        cfis.stay_id,
        cfis.intime,
        cfis.outtime,
        cfis.hospital_expire_flag,
        -- Calculate number of distinct procedures (0 if none found in window)
        COUNT(DISTINCT proc.icd_code) AS num_procedures,
        -- Calculate Length of Stay in days
        DATETIME_DIFF(cfis.outtime, cfis.intime, HOUR) / 24.0 AS los_days
    FROM
        cohort_first_icu_stays cfis
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp`.procedures_icd proc
        ON cfis.subject_id = proc.subject_id
        AND cfis.hadm_id = proc.hadm_id
        -- Procedures must occur within the first 72 hours (3 days) of ICU admission time
        AND proc.chartdate BETWEEN cfis.intime AND DATETIME_ADD(cfis.intime, INTERVAL 72 HOUR)
        AND proc.chartdate IS NOT NULL -- Ensure chartdate is not null for valid comparison
    GROUP BY
        cfis.subject_id,
        cfis.hadm_id,
        cfis.stay_id,
        cfis.intime,
        cfis.outtime,
        cfis.hospital_expire_flag
),
quartile_assigned_patients AS (
    -- Step 3: Assign quartiles based on the number of distinct procedures.
    SELECT
        ppc.subject_id,
        ppc.hadm_id,
        ppc.stay_id,
        ppc.intime,
        ppc.outtime,
        ppc.hospital_expire_flag,
        ppc.num_procedures,
        ppc.los_days,
        NTILE(4) OVER (ORDER BY ppc.num_procedures) AS quartile
    FROM
        patient_procedure_counts ppc
)
-- Step 4: Final aggregation by quartile to report requested metrics.
SELECT
    qap.quartile,
    COUNT(DISTINCT qap.subject_id) AS num_patients,
    MIN(qap.num_procedures) AS min_procedures_per_patient,
    MAX(qap.num_procedures) AS max_procedures_per_patient,
    AVG(qap.num_procedures) AS mean_procedures_per_patient,
    AVG(qap.los_days) AS mean_los_days,
    AVG(CASE WHEN qap.hospital_expire_flag = 1 THEN 100.0 ELSE 0.0 END) AS mortality_percentage
FROM
    quartile_assigned_patients qap
GROUP BY
    qap.quartile
ORDER BY
    qap.quartile;