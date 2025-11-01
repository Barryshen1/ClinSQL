WITH hadm_hf AS (
    SELECT DISTINCT hadm_id, subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND icd_code LIKE '428%') OR -- ICD-9 codes for Heart Failure
        (icd_version = 10 AND icd_code LIKE 'I50%')    -- ICD-10 codes for Heart Failure
),
-- CTE 2: Get the base cohort of male patients aged 40-50 with HF diagnosis
-- Joins admissions, patients, and the identified HF admissions.
-- Calculates age at admission and filters by gender and age.
base_cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        pat.gender,
         -- Calculate age at admission: anchor_age + (Year of admittime - anchor_year)
        (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) AS age_at_admission,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        -- Calculate LOS in days, including fractional days using seconds difference, directly here
        DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / (60 * 60 * 24.0) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN hadm_hf hf
        ON adm.hadm_id = hf.hadm_id
    WHERE
        pat.gender = 'M' -- Filter for male patients
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 40 AND 50 -- Apply age filter here
),
-- CTE 3: Calculate the 7-day medication complexity score
-- Counts the number of distinct medications prescribed/dispensed within the first 7 days of admission.
med_complexity AS (
    SELECT
        bc.subject_id,
        bc.hadm_id,
        COUNT(DISTINCT ph.medication) AS med_complexity_score
    FROM base_cohort bc
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph -- Changed to LEFT JOIN to include patients with no meds
        ON bc.hadm_id = ph.hadm_id
        AND ph.starttime >= bc.admittime
        AND ph.starttime <= DATETIME_ADD(bc.admittime, INTERVAL 7 DAY)
    GROUP BY bc.subject_id, bc.hadm_id
),
-- CTE 4: Calculate 30-day readmission flag for patients discharged alive
-- Identifies if a patient had another admission within 30 days of being discharged,
-- only considering those who survived the initial hospital stay.
readmission_30d AS (
    SELECT
        bc.subject_id,
        bc.hadm_id,
        MAX(CASE
            -- Flag as 1 if a subsequent admission exists within 30 days, otherwise 0
            WHEN adm_next.hadm_id IS NOT NULL THEN 1
            ELSE 0
        END) AS is_readmitted_30d
    FROM base_cohort bc
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm_next
        ON bc.subject_id = adm_next.subject_id
        AND adm_next.hadm_id != bc.hadm_id -- Ensure it's a different admission than the current one
        AND adm_next.admittime > bc.dischtime -- The next admission must start strictly after the current discharge
        AND adm_next.admittime <= DATETIME_ADD(bc.dischtime, INTERVAL 30 DAY) -- Within 30 days of current discharge
    WHERE
        bc.hospital_expire_flag = 0 -- Only consider patients discharged alive for readmission calculation
    GROUP BY bc.subject_id, bc.hadm_id
),
-- CTE 5: Combine all data, calculate derived metrics, AND assign quintiles
patient_metrics_with_quintile AS (
    SELECT
        bc.subject_id,
        bc.hadm_id,
        bc.age_at_admission,
        bc.admittime,
        bc.dischtime,
        bc.los_days, -- LOS already calculated in base_cohort
        bc.hospital_expire_flag,
        -- Use COALESCE to default medication complexity score to 0 if no medications were found
        COALESCE(mc.med_complexity_score, 0) AS med_complexity_score,
        -- Use COALESCE to default readmission flag to 0 if no readmission or patient died
        COALESCE(r30.is_readmitted_30d, 0) AS is_readmitted_30d,
        -- Assign quintiles based on medication complexity score after coalescing NULLs to 0
        NTILE(5) OVER (ORDER BY COALESCE(mc.med_complexity_score, 0) ASC) AS med_complexity_quintile
    FROM base_cohort bc
    LEFT JOIN med_complexity mc
        ON bc.subject_id = mc.subject_id AND bc.hadm_id = mc.hadm_id
    LEFT JOIN readmission_30d r30
        ON bc.subject_id = r30.subject_id AND bc.hadm_id = r30.hadm_id
)
-- Final step: Aggregate results by medication complexity quintile
SELECT
    med_complexity_quintile,
    COUNT(hadm_id) AS admission_count, -- Now directly referencing column from patient_metrics_with_quintile
    MIN(med_complexity_score) AS min_med_complexity_score,
    MAX(med_complexity_score) AS max_med_complexity_score,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_percent,
    ROUND(AVG(is_readmitted_30d) * 100, 2) AS readmission_30d_percent
FROM patient_metrics_with_quintile -- Referencing the CTE directly
GROUP BY med_complexity_quintile
ORDER BY med_complexity_quintile;