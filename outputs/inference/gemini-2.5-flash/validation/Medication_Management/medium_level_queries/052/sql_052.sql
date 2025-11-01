WITH cohort_raw AS (
    -- Initial selection of male patients aged 45-55 with ICU stays >= 48 hours
    SELECT
        p.subject_id,
        ad.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        icu.los
    FROM
        `physionet-data.mimiciv_3_1_hosp`.patients p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.admissions ad
        ON p.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu`.icustays icu
        ON ad.subject_id = icu.subject_id AND ad.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 45 AND 55
        AND icu.los >= 48 / 24.0 -- los is in days, so 48 hours = 2 days
),
cohort_with_diagnoses AS (
    -- Filter cohort for patients with both Type 2 Diabetes and Heart Failure diagnoses
    SELECT
        cr.subject_id,
        cr.hadm_id,
        cr.stay_id,
        cr.intime,
        cr.outtime,
        MAX(CASE
            WHEN (dicd.icd_version = 9 AND dicd.icd_code LIKE '250%' AND d_icd.long_title LIKE '%Type 2 diabetes mellitus%') OR
                 (dicd.icd_version = 10 AND dicd.icd_code LIKE 'E11%')
            THEN 1 ELSE 0 END
        ) AS has_type2_diabetes,
        MAX(CASE
            WHEN (dicd.icd_version = 9 AND dicd.icd_code LIKE '428%') OR
                 (dicd.icd_version = 10 AND dicd.icd_code LIKE 'I50%')
            THEN 1 ELSE 0 END
        ) AS has_heart_failure
    FROM
        cohort_raw cr
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd dicd
        ON cr.subject_id = dicd.subject_id AND cr.hadm_id = dicd.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_icd
        ON dicd.icd_code = d_icd.icd_code AND dicd.icd_version = d_icd.icd_version
    GROUP BY
        cr.subject_id, cr.hadm_id, cr.stay_id, cr.intime, cr.outtime
    HAVING
        has_type2_diabetes = 1 AND has_heart_failure = 1
),
final_cohort AS (
    -- The final cohort meeting all demographic and diagnostic criteria
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        intime,
        outtime
    FROM
        cohort_with_diagnoses
),
total_cohort_patients AS (
    -- Count total unique patients in the final cohort for percentage calculation
    SELECT
        COUNT(DISTINCT subject_id) AS total_patients
    FROM
        final_cohort
),
medications_administered AS (
    -- Identify Insulin and Oral Agents administered to the final cohort
    SELECT
        fc.subject_id,
        fc.hadm_id,
        fc.stay_id,
        fc.intime,
        fc.outtime,
        emar.charttime,
        CASE
            WHEN UPPER(emar.medication) LIKE '%INSULIN%' THEN 'Insulin'
            WHEN UPPER(emar.medication) IN (
                'METFORMIN', 'METFORMIN ER', 'METFORMIN HCL',
                'GLIPIZIDE', 'GLIPIZIDE ER',
                'GLYBURIDE', 'GLYBURIDE MICRO',
                'GLIMEPIRIDE',
                'PIOGLITAZONE',
                'ROSIGLITAZONE',
                'SITAGLIPTIN', 'SITAGLIPTIN/METFORMIN',
                'SAXAGLIPTIN', 'SAXAGLIPTIN/METFORMIN',
                'LINAGLIPTIN', 'LINAGLIPTIN/METFORMIN',
                'ALOGLIPTIN', 'ALOGLIPTIN/METFORMIN', 'ALOGLIPTIN/PIOGLITAZONE',
                'CANAGLIFLOZIN', 'CANAGLIFLOZIN/METFORMIN',
                'DAPAGLIFLOZIN', 'DAPAGLIFLOZIN/METFORMIN',
                'EMPAGLIFLOZIN', 'EMPAGLIFLOZIN/METFORMIN', 'EMPAGLIFLOZIN/LINAGLIPTIN',
                'ERTUGLIFLOZIN', 'ERTUGLIFLOZIN/METFORMIN', 'ERTUGLIFLOZIN/SITAGLIPTIN',
                'ACARBOSE',
                'MIGLITOL',
                'REPAGLINIDE',
                'NATEGLINIDE'
            ) THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%METFORMIN%' THEN 'Oral Agents' -- Catch formulations not explicitly listed
            WHEN UPPER(emar.medication) LIKE '%GLIPIZIDE%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%GLYBURIDE%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%GLIMEPIRIDE%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%PIOGLITAZONE%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%ROSIGLITAZONE%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%DAPAGLIFLOZIN%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%EMPAGLIFLOZIN%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%CANAGLIFLOZIN%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%SITAGLIPTIN%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%SAXAGLIPTIN%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%LINAGLIPTIN%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%ALOGLIPTIN%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%ERTUGLIFLOZIN%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%ACARBOSE%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%MIGLITOL%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%REPAGLINIDE%' THEN 'Oral Agents'
            WHEN UPPER(emar.medication) LIKE '%NATEGLINIDE%' THEN 'Oral Agents'
            ELSE 'Other'
        END AS medication_type
    FROM
        final_cohort fc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.emar emar
        ON fc.subject_id = emar.subject_id AND fc.hadm_id = emar.hadm_id
    WHERE
        emar.charttime IS NOT NULL AND
        (UPPER(emar.medication) LIKE '%INSULIN%' OR
         UPPER(emar.medication) LIKE '%METFORMIN%' OR
         UPPER(emar.medication) LIKE '%GLIPIZIDE%' OR
         UPPER(emar.medication) LIKE '%GLYBURIDE%' OR
         UPPER(emar.medication) LIKE '%GLIMEPIRIDE%' OR
         UPPER(emar.medication) LIKE '%PIOGLITAZONE%' OR
         UPPER(emar.medication) LIKE '%ROSIGLITAZONE%' OR
         UPPER(emar.medication) LIKE '%SITAGLIPTIN%' OR
         UPPER(emar.medication) LIKE '%SAXAGLIPTIN%' OR
         UPPER(emar.medication) LIKE '%LINAGLIPTIN%' OR
         UPPER(emar.medication) LIKE '%ALOGLIPTIN%' OR
         UPPER(emar.medication) LIKE '%CANAGLIFLOZIN%' OR
         UPPER(emar.medication) LIKE '%DAPAGLIFLOZIN%' OR
         UPPER(emar.medication) LIKE '%EMPAGLIFLOZIN%' OR
         UPPER(emar.medication) LIKE '%ERTUGLIFLOZIN%' OR
         UPPER(emar.medication) LIKE '%ACARBOSE%' OR
         UPPER(emar.medication) LIKE '%MIGLITOL%' OR
         UPPER(emar.medication) LIKE '%REPAGLINIDE%' OR
         UPPER(emar.medication) LIKE '%NATEGLINIDE%'
        )
),
medication_events_by_window AS (
    -- Determine which medications were administered in each time window
    SELECT
        ma.subject_id,
        ma.hadm_id,
        ma.stay_id,
        ma.medication_type,
        -- Check for administration in the first 48 hours
        CASE
            WHEN ma.charttime >= ma.intime AND ma.charttime <= DATETIME_ADD(ma.intime, INTERVAL 48 HOUR)
            THEN 1 ELSE 0
        END AS in_first_48h_window,
        -- Check for administration in the final 24 hours
        CASE
            WHEN ma.charttime >= DATETIME_SUB(ma.outtime, INTERVAL 24 HOUR) AND ma.charttime <= ma.outtime
            THEN 1 ELSE 0
        END AS in_final_24h_window
    FROM
        medications_administered ma
),
summary_by_patient_and_window AS (
    -- Summarize medication administration per patient for each window
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        MAX(CASE WHEN medication_type = 'Insulin' AND in_first_48h_window = 1 THEN 1 ELSE 0 END) AS received_insulin_first_48h,
        MAX(CASE WHEN medication_type = 'Oral Agents' AND in_first_48h_window = 1 THEN 1 ELSE 0 END) AS received_oral_first_48h,
        MAX(CASE WHEN medication_type = 'Insulin' AND in_final_24h_window = 1 THEN 1 ELSE 0 END) AS received_insulin_final_24h,
        MAX(CASE WHEN medication_type = 'Oral Agents' AND in_final_24h_window = 1 THEN 1 ELSE 0 END) AS received_oral_final_24h
    FROM
        medication_events_by_window
    GROUP BY
        subject_id, hadm_id, stay_id
),
final_counts AS (
    -- Count distinct patients for each medication type and window
    SELECT
        COUNT(DISTINCT CASE WHEN received_insulin_first_48h = 1 THEN subject_id END) AS insulin_first_48h_patients,
        COUNT(DISTINCT CASE WHEN received_oral_first_48h = 1 THEN subject_id END) AS oral_first_48h_patients,
        COUNT(DISTINCT CASE WHEN received_insulin_final_24h = 1 THEN subject_id END) AS insulin_final_24h_patients,
        COUNT(DISTINCT CASE WHEN received_oral_final_24h = 1 THEN subject_id END) AS oral_final_24h_patients
    FROM
        summary_by_patient_and_window
)
-- Calculate and present percentages
SELECT
    'First 48 Hours' AS time_window,
    'Insulin' AS medication_category,
    (fc.insulin_first_48h_patients / CAST(tcp.total_patients AS BIGNUMERIC)) * 100 AS percentage
FROM
    final_counts fc, total_cohort_patients tcp -- Using cross join, as total_cohort_patients is a single row
UNION ALL
SELECT
    'First 48 Hours' AS time_window,
    'Oral Agents' AS medication_category,
    (fc.oral_first_48h_patients / CAST(tcp.total_patients AS BIGNUMERIC)) * 100 AS percentage
FROM
    final_counts fc, total_cohort_patients tcp
UNION ALL
SELECT
    'Final 24 Hours' AS time_window,
    'Insulin' AS medication_category,
    (fc.insulin_final_24h_patients / CAST(tcp.total_patients AS BIGNUMERIC)) * 100 AS percentage
FROM
    final_counts fc, total_cohort_patients tcp
UNION ALL
SELECT
    'Final 24 Hours' AS time_window,
    'Oral Agents' AS medication_category,
    (fc.oral_final_24h_patients / CAST(tcp.total_patients AS BIGNUMERIC)) * 100 AS percentage
FROM
    final_counts fc, total_cohort_patients tcp
ORDER BY
    time_window, medication_category;