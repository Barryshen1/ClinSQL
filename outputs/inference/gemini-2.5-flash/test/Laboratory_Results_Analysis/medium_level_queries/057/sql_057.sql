WITH PatientAdmissions AS (
    -- Select male patients aged 79-89 years
    SELECT
        p.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 79 AND 89
),
ACSAdmissions AS (
    -- Filter for admissions with an Acute Coronary Syndrome (ACS) diagnosis
    SELECT DISTINCT
        pa.hadm_id
    FROM
        PatientAdmissions pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON pa.hadm_id = di.hadm_id
    WHERE
        (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code = '4111')) -- ICD-9: Acute MI (410.x), Unstable Angina (411.1)
        OR
        (di.icd_version = 10 AND (di.icd_code LIKE 'I20%' OR di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I24%')) -- ICD-10: Angina (I20.x, incl. unstable I20.0), MI (I21.x, I22.x), Other acute ischemic heart diseases (I24.x)
),
TroponinT_Labs AS (
    -- Get all Troponin T lab events for the identified ACS admissions
    SELECT
        acs.hadm_id,
        le.charttime,
        le.valuenum
    FROM
        ACSAdmissions acs
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON acs.hadm_id = le.hadm_id
    WHERE
        le.itemid = 51003 -- ItemID for Troponin T (Quant)
        AND le.valuenum IS NOT NULL -- Ensure a valid numeric value exists
),
IndexTroponinT AS (
    -- Find the first (index) Troponin T measurement for each admission
    SELECT
        hadm_id,
        valuenum AS first_troponin_t_value,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) as rn
    FROM
        TroponinT_Labs
)
-- Categorize the index Troponin T values and count admissions
SELECT
    CASE
        WHEN itt.first_troponin_t_value <= 0.04 THEN 'Normal (<= 0.04)'
        WHEN itt.first_troponin_t_value > 0.04 AND itt.first_troponin_t_value <= 0.1 THEN 'Borderline (> 0.04 - 0.1)'
        WHEN itt.first_troponin_t_value > 0.1 THEN 'Elevated (> 0.1)'
        ELSE 'Undetermined' -- Should ideally not be reached given prior filters, but good for completeness
    END AS troponin_t_category,
    COUNT(itt.hadm_id) AS admission_count
FROM
    IndexTroponinT itt
WHERE
    itt.rn = 1 -- Select only the first Troponin T measurement for each admission
GROUP BY
    troponin_t_category
ORDER BY
    CASE troponin_t_category
        WHEN 'Normal (<= 0.04)' THEN 1
        WHEN 'Borderline (> 0.04 - 0.1)' THEN 2
        WHEN 'Elevated (> 0.1)' THEN 3
        ELSE 4
    END;