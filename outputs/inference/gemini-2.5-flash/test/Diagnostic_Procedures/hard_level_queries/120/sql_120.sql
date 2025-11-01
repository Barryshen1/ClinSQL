WITH admissions_ugi AS (
    -- Identify hospital admissions with a primary diagnosis of Upper GI Bleeding
    SELECT DISTINCT adm.hadm_id, adm.subject_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    WHERE EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
            ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
        WHERE di.hadm_id = adm.hadm_id
        AND (
            -- ICD-9 codes for Upper GI Hemorrhage and related conditions
            (di.icd_version = 9 AND (
                di.icd_code LIKE '578%' -- Hematemesis, Melena, GI hemorrhage unspecified
                OR di.icd_code IN ('53082') -- Esophageal hemorrhage
                OR (di.icd_code BETWEEN '5310' AND '5339' AND dd.long_title LIKE '%hemorrhage%') -- Peptic ulcer with hemorrhage
                OR (di.icd_code LIKE '5355%' AND dd.long_title LIKE '%hemorrhage%') -- Gastritis/Duodenitis w/ hemorrhage (e.g., 535.51)
                OR (di.icd_code LIKE '53783%') -- Angiodysplasia (e.g., 537.83)
            ))
            OR
            -- ICD-10 codes for Upper GI Hemorrhage and related conditions
            (di.icd_version = 10 AND (
                di.icd_code LIKE 'K92%' -- Hematemesis, Melena, GI hemorrhage unspecified
                OR di.icd_code LIKE 'K25%' -- Gastric ulcer with hemorrhage
                OR di.icd_code LIKE 'K26%' -- Duodenal ulcer with hemorrhage
                OR di.icd_code LIKE 'K27%' -- Peptic ulcer, site unspecified with hemorrhage
                OR di.icd_code LIKE 'I850%' -- Esophageal varices with bleeding
                OR di.icd_code IN ('K226') -- Mallory-Weiss tear
                OR (di.icd_code LIKE 'K29__1' AND dd.long_title LIKE '%hemorrhage%') -- Gastritis/duodenitis with hemorrhage (e.g., K29.01, K29.11, etc.)
            ))
        )
    )
),
icustays_filtered AS (
    -- Filter for male patients aged 74-84 at admission, getting their first ICU stay
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age AS age_at_admission,
        ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn_stay
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN admissions_ugi adm
        ON icu.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON icu.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 74 AND 84
),
procedures_72h AS (
    -- Count all procedures within the first 72 hours of the *first* ICU stay
    SELECT
        iff.stay_id,
        COUNT(px.icd_code) AS diagnostic_procedure_count_72h
    FROM icustays_filtered iff
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` px
        ON iff.hadm_id = px.hadm_id
    WHERE
        iff.rn_stay = 1 -- Only consider the first ICU stay for these procedures
        AND px.chartdate >= DATE(iff.intime)
        AND px.chartdate < DATE(DATETIME_ADD(iff.intime, INTERVAL 72 HOUR)) -- Procedures within the first 72 hours (calendar days)
    GROUP BY
        iff.stay_id
),
patient_cohort AS (
    -- Combine all relevant patient and stay data with the procedure count
    SELECT
        iff.subject_id,
        iff.hadm_id,
        iff.stay_id,
        COALESCE(p72.diagnostic_procedure_count_72h, 0) AS diagnostic_procedure_count_72h, -- 0 if no procedures found in 72h
        DATETIME_DIFF(iff.dischtime, iff.admittime, HOUR) / 24.0 AS hospital_los_days,
        iff.hospital_expire_flag
    FROM icustays_filtered iff
    LEFT JOIN procedures_72h p72 -- Use LEFT JOIN to include patients with 0 procedures
        ON iff.stay_id = p72.stay_id
    WHERE iff.rn_stay = 1 -- Ensure we process only the first ICU stay for further analysis
),
quartile_assignment AS (
    -- Assign diagnostic intensity quartiles based on 72-hour procedure count
    SELECT
        *,
        NTILE(4) OVER (ORDER BY diagnostic_procedure_count_72h ASC) AS diagnostic_intensity_quartile
    FROM patient_cohort
)
-- Final aggregation and reporting
SELECT
    diagnostic_intensity_quartile,
    COUNT(DISTINCT subject_id) AS num_patients_in_quartile,
    COUNT(DISTINCT stay_id) AS num_icu_stays_in_quartile,
    AVG(diagnostic_procedure_count_72h) AS mean_72h_procedure_count,
    AVG(hospital_los_days) AS mean_hospital_los_days,
    AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent
FROM quartile_assignment
GROUP BY diagnostic_intensity_quartile
ORDER BY diagnostic_intensity_quartile;