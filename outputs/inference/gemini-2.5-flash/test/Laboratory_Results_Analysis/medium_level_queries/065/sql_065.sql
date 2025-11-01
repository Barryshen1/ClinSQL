WITH PatientAdmissionFilter AS (
    -- Step 1: Filter for male patients aged 49-59
    SELECT
        p.subject_id,
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 49 AND 59
),
AMI_Admissions AS (
    -- Step 2: Filter for admissions where AMI is the primary diagnosis (ICD-10)
    SELECT
        paf.subject_id,
        paf.hadm_id
    FROM
        PatientAdmissionFilter paf
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON paf.subject_id = di.subject_id AND paf.hadm_id = di.hadm_id
    WHERE
        di.icd_version = 10
        AND LEFT(di.icd_code, 3) IN ('I21', 'I22') -- ICD-10 codes for Acute Myocardial Infarction
        AND di.seq_num = 1 -- Principal diagnosis for the admission
    GROUP BY
        paf.subject_id, paf.hadm_id
),
TroponinT_Item AS (
    -- Step 3: Identify the itemid for Troponin T
    SELECT
        itemid
    FROM
        `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE
        LOWER(label) = 'troponin t'
),
FirstTroponinT_Value AS (
    -- Step 4: Get the first recorded Troponin T value for each relevant admission
    SELECT
        le.subject_id,
        le.hadm_id,
        le.valuenum AS troponin_t_value,
        ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime, le.labevent_id) as rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN
        TroponinT_Item tti
        ON le.itemid = tti.itemid
    WHERE
        le.valuenum IS NOT NULL AND le.valuenum >= 0
)
-- Final Step: Join AMI admissions with their first Troponin T values, apply the threshold, and calculate median and IQR
SELECT
    PERCENTILE_CONT(ftt.troponin_t_value, 0.5) OVER() AS median_initial_troponin_t,
    (PERCENTILE_CONT(ftt.troponin_t_value, 0.75) OVER() - PERCENTILE_CONT(ftt.troponin_t_value, 0.25) OVER()) AS iqr_initial_troponin_t
FROM
    AMI_Admissions ami
JOIN
    FirstTroponinT_Value ftt
    ON ami.subject_id = ftt.subject_id AND ami.hadm_id = ftt.hadm_id
WHERE
    ftt.rn = 1 -- Ensure we only take the very first measurement for each admission
    AND ftt.troponin_t_value > 0.04 -- Apply the specified threshold
LIMIT 1; -- The PERCENTILE_CONT functions with OVER() will return the same result for all rows, so LIMIT 1 is sufficient.;