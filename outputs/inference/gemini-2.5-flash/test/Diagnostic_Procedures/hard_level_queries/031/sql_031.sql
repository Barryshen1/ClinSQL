WITH cohort_patients AS (
    SELECT DISTINCT
        p.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        icu.stay_id,
        icu.intime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 66 AND 76
        -- Filter for admissions with Hyperglycemic Hyperosmolar State (HHS) diagnosis
        -- Using common ICD-10 codes for HHS. For MIMIC-IV, icd_version is typically 10.
        AND adm.hadm_id IN (
            SELECT DISTINCT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE icd_version = 10 AND icd_code IN ('E1165', 'E1365')
        )
),
-- Step 2: Calculate 48-hour procedure burden for each ICU stay in the cohort
icu_procedure_counts AS (
    SELECT
        cp.subject_id,
        cp.hadm_id,
        cp.stay_id,
        cp.intime,
        cp.admittime,
        cp.dischtime,
        cp.hospital_expire_flag,
        -- Count procedure events within 48 hours of ICU admission (intime)
        COUNT(pe.itemid) AS procedure_count_48hr
    FROM
        cohort_patients cp
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON cp.stay_id = pe.stay_id
        AND pe.starttime BETWEEN cp.intime AND TIMESTAMP_ADD(cp.intime, INTERVAL 48 HOUR)
    GROUP BY
        cp.subject_id, cp.hadm_id, cp.stay_id, cp.intime, cp.admittime, cp.dischtime, cp.hospital_expire_flag
),
-- Step 3: Assign quintiles based on procedure burden
icu_procedure_quintiles AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY procedure_count_48hr ASC) AS procedure_quintile
    FROM
        icu_procedure_counts
),
-- Step 4: Determine 30-day readmissions for the cohort's admissions
admissions_with_readmit_info AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.dischtime,
        -- Find the admittime of the next admission for the same patient
        LEAD(adm.admittime) OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) AS next_admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
),
-- Combine quintile information with all necessary outcome flags (per ICU stay)
final_cohort_stays_with_outcomes AS (
    SELECT
        q.procedure_quintile,
        q.subject_id,
        q.hadm_id,
        q.stay_id,
        q.procedure_count_48hr,
        q.hospital_expire_flag,
        TIMESTAMP_DIFF(q.dischtime, q.admittime, HOUR) / 24.0 AS hospital_los_days,
        -- Flag for 30-day readmission (1 if readmitted, 0 otherwise)
        CASE
            WHEN ar.next_admittime IS NOT NULL
            AND TIMESTAMP_DIFF(ar.next_admittime, q.dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END AS readmission_30day_flag
    FROM
        icu_procedure_quintiles q
    INNER JOIN
        admissions_with_readmit_info ar
        ON q.subject_id = ar.subject_id AND q.hadm_id = ar.hadm_id
)
-- Step 5: Final aggregation per quintile
SELECT
    fcs.procedure_quintile,
    COUNT(fcs.stay_id) AS num_icu_stays, -- Count all ICU stays within the quintile
    ROUND(AVG(fcs.procedure_count_48hr), 2) AS mean_procedures_48hr,
    MIN(fcs.procedure_count_48hr) AS min_procedures_48hr,
    MAX(fcs.procedure_count_48hr) AS max_procedures_48hr,
    -- Calculate hospital mortality percentage based on unique admissions per quintile
    ROUND(
        COUNT(DISTINCT CASE WHEN fcs.hospital_expire_flag = 1 THEN fcs.hadm_id ELSE NULL END) * 100.0 / COUNT(DISTINCT fcs.hadm_id),
        2
    ) AS hospital_mortality_percent,
    -- Calculate mean hospital LOS based on unique admissions per quintile
    ROUND(AVG(DISTINCT fcs.hospital_los_days), 2) AS mean_hospital_los_days,
    -- Calculate 30-day readmission percentage based on unique admissions per quintile
    ROUND(
        COUNT(DISTINCT CASE WHEN fcs.readmission_30day_flag = 1 THEN fcs.hadm_id ELSE NULL END) * 100.0 / COUNT(DISTINCT fcs.hadm_id),
        2
    ) AS readmission_30day_percent
FROM
    final_cohort_stays_with_outcomes fcs
GROUP BY
    fcs.procedure_quintile
ORDER BY
    fcs.procedure_quintile;