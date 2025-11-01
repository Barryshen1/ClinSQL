WITH high_risk_drugs AS (
    -- Define a list of high-risk drugs. This list should be clinically validated.
    -- Using common drug names (case-insensitive for matching).
    SELECT 'INSULIN' AS drug_name_upper UNION ALL
    SELECT 'HEPARIN' UNION ALL
    SELECT 'WARFarin' UNION ALL
    SELECT 'FENTANYL' UNION ALL
    SELECT 'MORPHINE' UNION ALL
    SELECT 'HYDROmorphone' UNION ALL
    SELECT 'PROPOFOL' UNION ALL
    SELECT 'NOREPINEPHRINE' UNION ALL
    SELECT 'EPINEPHRINE' UNION ALL
    SELECT 'DOPAMINE' UNION ALL
    SELECT 'POTASSIUM CHLORIDE' UNION ALL
    SELECT 'VECURONIUM' UNION ALL
    SELECT 'ROCURONIUM'
),
cohort_admissions AS (
    -- Identify the target patient cohort:
    -- Females, age 78-88, admitted for post-cardiac arrest.
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 78 AND 88
        -- Filtering for typical admission types for acute events like cardiac arrest
        AND ad.admission_type IN ('EMERGENCY', 'URGENT', 'DIRECT EMER.')
        -- Check for cardiac arrest diagnosis during the admission
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.subject_id = ad.subject_id
                AND di.hadm_id = ad.hadm_id
                AND di.icd_version IN (9, 10)
                AND (
                    -- ICD-9 code for cardiac arrest
                    (di.icd_version = 9 AND di.icd_code = '4275')
                    -- ICD-10 codes for cardiac arrest
                    OR (di.icd_version = 10 AND di.icd_code IN ('I462', 'I468', 'I469'))
                )
        )
),
medication_details AS (
    -- Extract medication details for the first 7 days of admission for the cohort
    SELECT
        ca.subject_id,
        ca.hadm_id,
        p.drug AS medication_name,
        p.route AS medication_route,
        -- Flag if the medication is a high-risk drug
        CASE
            WHEN UPPER(p.drug) IN (SELECT drug_name_upper FROM high_risk_drugs) THEN 1
            ELSE 0
        END AS is_high_risk_drug
    FROM
        cohort_admissions ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON ca.subject_id = p.subject_id AND ca.hadm_id = p.hadm_id
    WHERE
        p.starttime IS NOT NULL
        AND p.starttime >= ca.admittime
        AND p.starttime < DATETIME_ADD(ca.admittime, INTERVAL 7 DAY)
),
med_complexity_scores AS (
    -- Aggregate medication characteristics to calculate components of the complexity score
    SELECT
        md.subject_id,
        md.hadm_id,
        COUNT(DISTINCT md.medication_name) AS unique_drugs,
        -- Count distinct high-risk drugs prescribed
        COUNT(DISTINCT CASE WHEN md.is_high_risk_drug = 1 THEN md.medication_name END) AS num_distinct_high_risk_drugs,
        COUNT(DISTINCT md.medication_route) AS unique_routes
    FROM
        medication_details md
    GROUP BY
        md.subject_id, md.hadm_id
),
admission_details_with_readmission AS (
    -- Calculate hospital Length of Stay (LOS) and 30-day readmission status
    SELECT
        ca.subject_id,
        ca.hadm_id,
        DATETIME_DIFF(ca.dischtime, ca.admittime, HOUR) / 24.0 AS hospital_los,
        ca.hospital_expire_flag,
        -- Determine if there is a subsequent readmission within 30 days
        CASE
            WHEN
                LEAD(ca.admittime, 1) OVER (PARTITION BY ca.subject_id ORDER BY ca.admittime) IS NOT NULL
                AND DATETIME_DIFF(LEAD(ca.admittime, 1) OVER (PARTITION BY ca.subject_id ORDER BY ca.admittime), ca.dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END AS readmission_30_day_flag
    FROM
        cohort_admissions ca
),
patient_data_with_complexity AS (
    -- Combine admission details with medication complexity scores
    SELECT
        ad.subject_id,
        ad.hadm_id,
        -- Calculate the final complexity score: (unique drugs + 2 * high-risk drugs + routes)
        -- Use COALESCE to handle cases where an admission had no prescriptions in the 7-day window.
        (COALESCE(mcs.unique_drugs, 0) + (2 * COALESCE(mcs.num_distinct_high_risk_drugs, 0)) + COALESCE(mcs.unique_routes, 0)) AS complexity_score,
        ad.hospital_los,
        ad.hospital_expire_flag,
        ad.readmission_30_day_flag
    FROM
        admission_details_with_readmission ad
    LEFT JOIN -- Use LEFT JOIN to include all cohort admissions, even if no prescriptions are found
        med_complexity_scores mcs
        ON ad.subject_id = mcs.subject_id AND ad.hadm_id = mcs.hadm_id
),
patient_data_with_tertiles AS (
    -- Assign medication complexity tertiles to each admission
    SELECT
        subject_id,
        hadm_id,
        complexity_score,
        hospital_los,
        hospital_expire_flag,
        readmission_30_day_flag,
        NTILE(3) OVER (ORDER BY complexity_score) AS medication_complexity_tertile
    FROM
        patient_data_with_complexity
)
-- Final aggregation to report the required metrics by tertile
SELECT
    medication_complexity_tertile,
    COUNT(DISTINCT hadm_id) AS patient_count,
    MIN(complexity_score) AS min_complexity_score,
    MAX(complexity_score) AS max_complexity_score,
    ROUND(AVG(hospital_los), 2) AS mean_hospital_los_days,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS in_hospital_mortality_percent,
    ROUND(SUM(readmission_30_day_flag) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS readmission_30_day_percent
FROM
    patient_data_with_tertiles
GROUP BY
    medication_complexity_tertile
ORDER BY
    medication_complexity_tertile;