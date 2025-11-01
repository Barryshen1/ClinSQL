WITH PatientCohort AS (
    -- Step 1: Identify the initial patient cohort (males, 83-93 years) and calculate Length of Stay (LOS).
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 83 AND 93
),
ACS_Admissions AS (
    -- Step 2: Identify admissions with Acute Coronary Syndrome (ACS) diagnoses and determine if primary or secondary.
    -- ACS ICD-9 codes: 410% (Acute MI), 411.1 (Unstable Angina), 411.8% (Other acute ischemic HD)
    -- ACS ICD-10 codes: I20.0 (Unstable Angina), I21% (Acute MI), I22% (Subsequent MI), I24% (Other acute ischemic HD)
    SELECT
        pc.subject_id,
        pc.hadm_id,
        pc.los_days,
        -- Determine if ACS is a primary (seq_num=1) or secondary diagnosis for the admission
        CASE
            WHEN MAX(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'Primary ACS'
            ELSE 'Secondary ACS'
        END AS acs_diagnosis_type
    FROM
        PatientCohort AS pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON pc.hadm_id = di.hadm_id
    WHERE
        -- Filter for Acute Coronary Syndrome (ACS) diagnosis codes
        (
            di.icd_version = 9 AND (
                di.icd_code LIKE '410%' OR di.icd_code = '411.1' OR di.icd_code LIKE '411.8%'
            )
        ) OR (
            di.icd_version = 10 AND (
                di.icd_code = 'I20.0' OR di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I24%'
            )
        )
    GROUP BY
        pc.subject_id,
        pc.hadm_id,
        pc.los_days
    HAVING
        -- Ensure at least one ACS diagnosis was found for the admission
        COUNT(di.icd_code) > 0
),
UltrasoundProcedures AS (
    -- Step 3: Count ultrasound-related procedures for each admission.
    SELECT
        pro.hadm_id,
        COUNT(pro.icd_code) AS num_ultrasounds -- Count all relevant ultrasound procedures for the admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pro
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dip
        ON pro.icd_code = dip.icd_code AND pro.icd_version = dip.icd_version
    WHERE
        -- Filter for procedure descriptions indicating ultrasound, echocardiogram, or doppler
        LOWER(dip.long_title) LIKE '%ultrasound%' OR
        LOWER(dip.long_title) LIKE '%echocardiogram%' OR
        LOWER(dip.long_title) LIKE '%doppler%'
    GROUP BY
        pro.hadm_id
)
-- Step 4: Combine the information and perform final aggregation.
SELECT
    CASE
        WHEN aa.los_days BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN aa.los_days BETWEEN 5 AND 7 THEN '5-7 days'
        ELSE 'Other/Excluded LOS' -- Should be filtered out by WHERE clause
    END AS los_group,
    aa.acs_diagnosis_type,
    COUNT(DISTINCT aa.hadm_id) AS num_admissions,
    AVG(COALESCE(up.num_ultrasounds, 0)) AS mean_ultrasounds_per_admission,
    MIN(COALESCE(up.num_ultrasounds, 0)) AS min_ultrasounds_per_admission,
    MAX(COALESCE(up.num_ultrasounds, 0)) AS max_ultrasounds_per_admission
FROM
    ACS_Admissions AS aa
LEFT JOIN
    UltrasoundProcedures AS up
    ON aa.hadm_id = up.hadm_id
WHERE
    -- Filter for the specified length of stay ranges
    aa.los_days BETWEEN 1 AND 7
GROUP BY
    los_group,
    aa.acs_diagnosis_type
ORDER BY
    los_group,
    acs_diagnosis_type;