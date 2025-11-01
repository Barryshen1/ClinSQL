WITH base_admissions AS (
    -- Step 1: Identify eligible female patients aged 85-95 at admission
    SELECT
        pat.subject_id,
        adm.hadm_id,
        pat.gender,
        (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age AS age_at_admission,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON pat.subject_id = adm.subject_id
    WHERE
        pat.gender = 'F'
        AND ((EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age) BETWEEN 85 AND 95
),
asthma_admissions AS (
    -- Step 2: Filter for admissions with an asthma diagnosis (asthma exacerbation)
    SELECT DISTINCT ba.subject_id, ba.hadm_id, ba.hospital_expire_flag
    FROM base_admissions AS ba
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON ba.subject_id = di.subject_id AND ba.hadm_id = di.hadm_id
    WHERE
        (
            (di.icd_version = 9 AND LEFT(di.icd_code, 3) = '493') -- ICD-9 asthma codes (e.g., 493.xx)
            OR
            (di.icd_version = 10 AND LEFT(di.icd_code, 3) = 'J45') -- ICD-10 asthma codes (e.g., J45.xx)
        )
),
comorbidity_complications AS (
    -- Step 3: Calculate composite comorbidity score (count of distinct non-asthma diagnoses)
    -- and identify cardiovascular and neurologic complications for each asthma admission
    SELECT
        aa.subject_id,
        aa.hadm_id,
        aa.hospital_expire_flag,
        -- Composite comorbidity score: Count of distinct non-asthma ICD codes for the admission
        COUNT(DISTINCT
            CASE
                WHEN
                    NOT (
                        (di.icd_version = 9 AND LEFT(di.icd_code, 3) = '493') OR
                        (di.icd_version = 10 AND LEFT(di.icd_code, 3) = 'J45')
                    )
                THEN di.icd_code
                ELSE NULL
            END
        ) AS comorbidity_score,
        -- Cardiovascular Complications Flag (1 if present, 0 otherwise)
        MAX(CASE
            WHEN
                (di.icd_version = 9 AND (
                    LEFT(di.icd_code, 3) = '410' OR                     -- Acute Myocardial Infarction
                    LEFT(di.icd_code, 3) = '428' OR                     -- Heart Failure
                    LEFT(di.icd_code, 3) IN ('433', '434', '436', '437', '438') OR -- Cerebrovascular accident/Stroke
                    LEFT(di.icd_code, 4) = '4273' OR                      -- Atrial Fibrillation/Flutter (e.g., 42731)
                    LEFT(di.icd_code, 4) = '4151' OR                      -- Pulmonary Embolism (e.g., 41519)
                    LEFT(di.icd_code, 3) IN ('401', '402', '403', '404', '405') -- Hypertension and hypertensive heart/renal disease
                )) OR
                (di.icd_version = 10 AND (
                    LEFT(di.icd_code, 3) IN ('I21', 'I22') OR          -- Acute Myocardial Infarction
                    LEFT(di.icd_code, 3) = 'I50' OR                     -- Heart Failure
                    LEFT(di.icd_code, 3) IN ('I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69') OR -- Cerebrovascular accident/Stroke
                    LEFT(di.icd_code, 3) = 'I48' OR                     -- Atrial Fibrillation/Flutter
                    LEFT(di.icd_code, 3) = 'I26' OR                     -- Pulmonary Embolism
                    LEFT(di.icd_code, 3) IN ('I10', 'I11', 'I12', 'I13', 'I14', 'I15', 'I16') -- Hypertension and related
                ))
            THEN 1 ELSE 0
        END) AS cardiovascular_complication,
        -- Neurologic Complications Flag (1 if present, 0 otherwise)
        MAX(CASE
            WHEN
                (di.icd_version = 9 AND (
                    LEFT(di.icd_code, 3) = '345' OR                     -- Seizures/Epilepsy
                    LEFT(di.icd_code, 4) = '2930' OR                      -- Delirium
                    LEFT(di.icd_code, 4) = '3483' OR                      -- Encephalopathy
                    LEFT(di.icd_code, 5) = '78001' OR                     -- Coma (e.g., 78001)
                    LEFT(di.icd_code, 4) = '3570' OR                      -- Acute polyneuropathy (e.g., Guillain-Barré)
                    LEFT(di.icd_code, 3) BETWEEN '320' AND '322'      -- Meningitis/Encephalitis
                )) OR
                (di.icd_version = 10 AND (
                    LEFT(di.icd_code, 3) IN ('G40', 'G41') OR          -- Seizures/Epilepsy
                    LEFT(di.icd_code, 3) = 'F05' OR                     -- Delirium
                    LEFT(di.icd_code, 4) = 'G934' OR                     -- Encephalopathy (e.g., G934)
                    LEFT(di.icd_code, 4) = 'R402' OR                     -- Coma (e.g., R402)
                    LEFT(di.icd_code, 4) = 'G610' OR                     -- Acute polyneuropathy
                    LEFT(di.icd_code, 3) IN ('G00', 'G01', 'G02', 'G03', 'G04', 'G05', 'G06', 'G07', 'G08') -- Meningitis/Encephalitis
                ))
            THEN 1 ELSE 0
        END) AS neurologic_complication
    FROM
        asthma_admissions AS aa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON aa.subject_id = di.subject_id AND aa.hadm_id = di.hadm_id
    GROUP BY
        aa.subject_id, aa.hadm_id, aa.hospital_expire_flag
),
admission_quartiles AS (
    -- Step 4: Assign each admission to a comorbidity quartile
    SELECT
        hadm_id,
        hospital_expire_flag,
        cardiovascular_complication,
        neurologic_complication,
        comorbidity_score,
        NTILE(4) OVER (ORDER BY comorbidity_score ASC) AS comorbidity_quartile
    FROM
        comorbidity_complications
)
-- Step 5: Final aggregation to report rates per quartile
SELECT
    comorbidity_quartile,
    COUNT(hadm_id) AS num_admissions,
    -- In-hospital mortality rate (as percentage)
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(hadm_id), 2) AS in_hospital_mortality_rate_percent,
    -- Cardiovascular complication rate (as percentage)
    ROUND(SUM(cardiovascular_complication) * 100.0 / COUNT(hadm_id), 2) AS cardiovascular_complication_rate_percent,
    -- Neurologic complication rate (as percentage)
    ROUND(SUM(neurologic_complication) * 100.0 / COUNT(hadm_id), 2) AS neurologic_complication_rate_percent
FROM
    admission_quartiles
GROUP BY
    comorbidity_quartile
ORDER BY
    comorbidity_quartile;