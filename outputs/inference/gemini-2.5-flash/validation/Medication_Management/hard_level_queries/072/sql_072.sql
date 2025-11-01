WITH dka_cohort AS (
    -- Identifies the base cohort: female, age 84-94 (interpreted as anchor_age 84-90), DKA diagnosis at admission.
    SELECT DISTINCT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        -- Filter for anchor_age 84 to 90. In MIMIC-IV, '90' represents 90+ years old.
        AND p.anchor_age BETWEEN 84 AND 90
        -- REMOVED: AND a.pediatric_hosp_flg = 0 (column does not exist in MIMIC-IV v3.1)
        AND a.admittime IS NOT NULL -- Ensure valid admission and discharge times
        AND a.dischtime IS NOT NULL
        AND (
            -- ICD-9 codes for DKA
            (di.icd_version = 9 AND di.icd_code IN ('25010', '25011', '25012', '25013')) OR
            -- ICD-10 codes for Type 1, Type 2, other specified, and unspecified DM with DKA
            (di.icd_version = 10 AND di.icd_code IN ('E1010', 'E1011', 'E1110', 'E1111', 'E1310', 'E1311', 'E1410', 'E1411'))
        )
),
patient_med_data AS (
    -- Gathers medication complexity and flags for hyperkalemia-risk drug exposure within the first 48 hours.
    SELECT
        dka.hadm_id,
        dka.subject_id,
        dka.admittime,
        dka.dischtime,
        dka.hospital_expire_flag,
        COUNT(DISTINCT pr.drug) AS medication_complexity_raw,
        -- Flag patients who received at least one medication from a hyperkalemia-risk drug class
        MAX(
            CASE
                WHEN
                    pr.drug LIKE '%lisinopril%' OR pr.drug LIKE '%ramipril%' OR pr.drug LIKE '%enalapril%' OR pr.drug LIKE '%benazepril%' OR pr.drug LIKE '%captopril%' OR pr.drug LIKE '%fosinopril%' OR pr.drug LIKE '%moexipril%' OR pr.drug LIKE '%perindopril%' OR pr.drug LIKE '%quinapril%' OR pr.drug LIKE '%trandolapril%' OR -- ACE Inhibitors
                    pr.drug LIKE '%valsartan%' OR pr.drug LIKE '%losartan%' OR pr.drug LIKE '%candesartan%' OR pr.drug LIKE '%irbesartan%' OR pr.drug LIKE '%olmesartan%' OR pr.drug LIKE '%telmisartan%' OR pr.drug LIKE '%eprosartan%' OR -- ARBs
                    pr.drug LIKE '%spironolactone%' OR pr.drug LIKE '%eplerenone%' OR pr.drug LIKE '%amiloride%' OR pr.drug LIKE '%triamterene%' OR -- K-sparing Diuretics
                    pr.drug LIKE '%potassium chloride%' OR pr.drug LIKE '%k-dur%' OR pr.drug LIKE '%klor-con%' OR pr.drug LIKE '%micro-k%' OR -- Potassium Supplements
                    pr.drug LIKE '%trimethoprim%' OR pr.drug LIKE '%bactrim%' OR pr.drug LIKE '%sulfamethoxazole%' -- Trimethoprim/Sulfamethoxazole (e.g., Bactrim)
                THEN 1
                ELSE 0
            END
        ) AS has_hyperkalemia_risk_drugs_flag
    FROM
        dka_cohort dka
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON dka.subject_id = pr.subject_id AND dka.hadm_id = pr.hadm_id
        -- Medications prescribed within the first 48 hours of admission
        AND pr.starttime BETWEEN dka.admittime AND dka.admittime + INTERVAL '48' HOUR
    GROUP BY
        dka.hadm_id, dka.subject_id, dka.admittime, dka.dischtime, dka.hospital_expire_flag
),
patient_features_with_percentile AS (
    -- Calculates LOS, handles missing complexity, and determines complexity percentile and quartile for each patient.
    SELECT
        hadm_id,
        subject_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        COALESCE(medication_complexity_raw, 0) AS medication_complexity, -- Treat no prescriptions within 48h as 0 complexity
        has_hyperkalemia_risk_drugs_flag,
        DATE_DIFF(dischtime, admittime, DAY) AS los_days,
        -- Calculate the percentile rank of medication complexity for each patient across the entire cohort
        ROUND(CUME_DIST() OVER (ORDER BY COALESCE(medication_complexity_raw, 0)) * 100, 2) AS medication_complexity_percentile,
        -- Determine the complexity quartile (1 = highest complexity, 4 = lowest)
        NTILE(4) OVER (ORDER BY COALESCE(medication_complexity_raw, 0) DESC) AS complexity_quartile
    FROM
        patient_med_data
)
-- Main query: Compare outcomes for patients with vs. without hyperkalemia-risk drugs
SELECT
    CASE
        WHEN has_hyperkalemia_risk_drugs_flag = 1 THEN 'With Hyperkalemia-Risk Drugs'
        ELSE 'Without Hyperkalemia-Risk Drugs'
    END AS group_name,
    COUNT(DISTINCT hadm_id) AS patient_count,
    ROUND(AVG(medication_complexity), 2) AS mean_medication_complexity,
    ROUND(AVG(medication_complexity_percentile), 2) AS avg_med_complexity_percentile,
    ROUND(AVG(los_days), 2) AS average_los_days,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS mortality_rate_percent
FROM
    patient_features_with_percentile
GROUP BY
    has_hyperkalemia_risk_drugs_flag

UNION ALL

-- Additional report: LOS and mortality for the top complexity quartile overall
SELECT
    'Top Complexity Quartile Overall' AS group_name,
    COUNT(DISTINCT hadm_id) AS patient_count,
    ROUND(AVG(medication_complexity), 2) AS mean_medication_complexity,
    ROUND(AVG(medication_complexity_percentile), 2) AS avg_med_complexity_percentile,
    ROUND(AVG(los_days), 2) AS average_los_days,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS mortality_rate_percent
FROM
    patient_features_with_percentile
WHERE
    complexity_quartile = 1 -- Selects patients in the top quartile of medication complexity
;