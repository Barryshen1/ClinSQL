WITH ACS_admissions AS (
    -- Identify unique hospital admissions (hadm_id) associated with suspected ACS diagnoses
    SELECT DISTINCT hadm_id, subject_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE 
        (icd_version = 10 AND (
            starts_with(icd_code, 'I20') OR -- Angina Pectoris (e.g., I20.0 for Unstable Angina)
            starts_with(icd_code, 'I21') OR -- Acute Myocardial Infarction
            starts_with(icd_code, 'I22') OR -- Subsequent STEMI and NSTEMI
            starts_with(icd_code, 'I24')    -- Other Acute Ischemic Heart Disease
        ))
        OR 
        (icd_version = 9 AND (
            starts_with(icd_code, '410') OR -- Acute Myocardial Infarction
            icd_code = '4111' OR            -- Unstable Angina
            starts_with(icd_code, '4118')   -- Other acute and subacute forms of ischemic heart disease
        ))
),
PatientAdmissionData AS (
    -- Filter admissions based on demographics (female, age 46-56) and calculate LOS
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        p.gender,
        p.anchor_age,
        -- Calculate hospital length of stay in days
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions ad
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
        ON ad.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 46 AND 56 -- Age filter as per question
),
FirstTnT AS (
    -- Find the first hs-TnT (Troponin T) lab result for each admission
    SELECT
        le.subject_id,
        le.hadm_id,
        le.charttime,
        le.valuenum,
        ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC, le.labevent_id ASC) AS rn -- Consider labevent_id for tie-breaking
    FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
    WHERE 
        le.itemid = 51003 -- itemid for 'Troponin T' in d_labitems (commonly used for hs-TnT in MIMIC)
        AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
),
CategorizedTnT AS (
    -- Categorize the first hs-TnT result into Normal, Borderline, or Myocardial Injury
    SELECT
        f.subject_id,
        f.hadm_id,
        -- Apply clinical thresholds for hs-TnT (values in ng/L)
        CASE
            WHEN f.valuenum < 6 THEN 'Normal'
            WHEN f.valuenum >= 6 AND f.valuenum <= 15 THEN 'Borderline'
            WHEN f.valuenum > 15 THEN 'Myocardial Injury'
            ELSE 'Unknown' -- Fallback, though not expected with valuenum IS NOT NULL
        END AS tnt_category
    FROM FirstTnT f
    WHERE f.rn = 1 -- Select only the first lab event for hs-TnT for each admission
)
-- Final aggregation to calculate counts, percentages, and mean LOS
SELECT
    ct.tnt_category,
    COUNT(DISTINCT pa.hadm_id) AS admission_count,
    -- Calculate percentage of total qualifying admissions
    ROUND(COUNT(DISTINCT pa.hadm_id) * 100.0 / SUM(COUNT(DISTINCT pa.hadm_id)) OVER (), 2) AS percentage,
    ROUND(AVG(pa.los_days), 2) AS mean_los_days_hospital
FROM PatientAdmissionData pa
INNER JOIN ACS_admissions acs
    ON pa.subject_id = acs.subject_id AND pa.hadm_id = acs.hadm_id
INNER JOIN CategorizedTnT ct
    ON pa.subject_id = ct.subject_id AND pa.hadm_id = ct.hadm_id
GROUP BY ct.tnt_category
ORDER BY ct.tnt_category;