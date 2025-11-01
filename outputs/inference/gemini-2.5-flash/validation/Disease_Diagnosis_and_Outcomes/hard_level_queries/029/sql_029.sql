WITH PneumoniaAdmissions AS (
    -- Step 1.1: Identify all female patients within the specified age range at admission
    -- who have a pneumonia diagnosis during that hospital admission.
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.deathtime,
        p.dod,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        -- Calculate age at the time of the current admission
        (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_current_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 82 AND 92
        -- Step 1.2: Filter for pneumonia diagnosis during the admission using ICD codes
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE di.hadm_id = adm.hadm_id
            AND (
                -- ICD-9 codes for pneumonia (480-486)
                (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^48[0-6]'))
                OR
                -- ICD-10 codes for pneumonia (J10-J18)
                (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^J1[0-8]'))
            )
        )
),
AdmissionsWithOutcomes AS (
    -- Step 2: Calculate outcomes for each identified pneumonia admission
    SELECT
        pa.subject_id,
        pa.hadm_id,
        pa.admittime,
        pa.dischtime,
        pa.age_at_current_admission,
        -- 30-day mortality flag: 1 if patient died within 30 days of admission, else 0
        CASE
            WHEN (COALESCE(pa.deathtime, pa.dod) IS NOT NULL AND DATE_DIFF(COALESCE(pa.deathtime, pa.dod), pa.admittime, DAY) <= 30) THEN 1
            ELSE 0
        END AS thirty_day_mortality_flag,
        -- Cardiovascular complication flag: 1 if relevant diagnosis present, else 0
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
                WHERE di.hadm_id = pa.hadm_id
                AND (
                    -- ICD-9 codes for CV complications (e.g., AMI, HF, Arrhythmias, Cardiomyopathy, CAD)
                    (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(410|412|428|427|425|414)'))
                    OR
                    -- ICD-10 codes for CV complications (e.g., AMI, HF, Arrhythmias, Cardiomyopathy, CAD)
                    (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(I21|I22|I50|I4[7-9]|I42|I25)'))
                )
            ) THEN 1
            ELSE 0
        END AS cv_complication_flag,
        -- Neurologic complication flag: 1 if relevant diagnosis present, else 0 (includes cerebrovascular events)
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
                WHERE di.hadm_id = pa.hadm_id
                AND (
                    -- ICD-9 codes for Neuro complications (e.g., Stroke, Seizure, Encephalopathy, Delirium, Coma/AMS)
                    (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(43[0-8]|345|348\.3|293\.0|293\.1|780\.(0[1-2]|09))'))
                    OR
                    -- ICD-10 codes for Neuro complications (e.g., Stroke, Seizure, Encephalopathy, Delirium, AMS/Coma, TIA)
                    (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(I6|G4[0-1]|G93\.4|F05|R40|G45)'))
                )
            ) THEN 1
            ELSE 0
        END AS neuro_complication_flag,
        -- Length of Stay in days
        DATE_DIFF(pa.dischtime, pa.admittime, HOUR) / 24.0 AS los_days
    FROM
        PneumoniaAdmissions pa
    WHERE
        pa.dischtime IS NOT NULL AND pa.admittime IS NOT NULL -- Ensure LOS can be calculated
),
AdmissionsWithRiskScore AS (
    -- Step 3: Simulate a composite risk score for each admission.
    -- In a real study, this would likely be a pre-calculated column or derived from a complex model.
    SELECT
        *,
        RAND() AS risk_score -- Using RAND() for demonstration purposes
    FROM
        AdmissionsWithOutcomes
),
AdmissionsWithQuintiles AS (
    -- Step 4: Assign each admission to a risk quintile based on the simulated risk score.
    -- NTILE(5) divides the ordered dataset into 5 almost equally sized groups.
    SELECT
        *,
        NTILE(5) OVER (ORDER BY risk_score ASC) AS risk_quintile
    FROM
        AdmissionsWithRiskScore
)
-- Step 5: Final aggregation to report metrics by risk quintile
SELECT
    aq.risk_quintile,
    COUNT(DISTINCT aq.hadm_id) AS total_admissions_in_quintile,
    -- 30-day mortality rate (average of the flag)
    AVG(aq.thirty_day_mortality_flag) AS thirty_day_mortality_rate,
    -- Cardiovascular complication rate (average of the flag)
    AVG(aq.cv_complication_flag) AS cardiovascular_complication_rate,
    -- Neurologic complication rate (average of the flag)
    AVG(aq.neuro_complication_flag) AS neurologic_complication_rate,
    -- Median LOS among survivors (where 30-day mortality flag is 0)
    APPROX_QUANTILES(
        CASE WHEN aq.thirty_day_mortality_flag = 0 AND aq.los_days IS NOT NULL THEN aq.los_days ELSE NULL END,
        100
    )[OFFSET(50)] AS median_los_among_survivors
FROM
    AdmissionsWithQuintiles aq
GROUP BY
    aq.risk_quintile
ORDER BY
    aq.risk_quintile;