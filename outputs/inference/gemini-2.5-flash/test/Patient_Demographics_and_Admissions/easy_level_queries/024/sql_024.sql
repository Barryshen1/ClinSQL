WITH PatientAdmissionsRanked AS (
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.hospital_expire_flag,
        -- Rank admissions by time to identify the first one for each patient
        ROW_NUMBER() OVER (PARTITION BY pa.subject_id ORDER BY ad.admittime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 35 AND 45 -- Filter for females aged 35-45
),
-- Select admissions that are the patient's first and included a CABG procedure
CABG_First_Admissions AS (
    SELECT
        par.subject_id,
        par.hadm_id,
        par.hospital_expire_flag
    FROM
        PatientAdmissionsRanked par
    JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr_icd
        ON par.hadm_id = pr_icd.hadm_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
        ON pr_icd.icd_code = d_proc.icd_code
        AND pr_icd.icd_version = d_proc.icd_version
    WHERE
        par.rn = 1 -- Only consider the first admission for each patient
        AND d_proc.long_title LIKE '%Coronary Artery Bypass%' -- Filter for CABG procedures
    GROUP BY
        par.subject_id,
        par.hadm_id,
        par.hospital_expire_flag -- Group to ensure unique admissions after joins
)
-- Calculate the in-hospital mortality rate from the identified CABG admissions
SELECT
    COUNTIF(cfa.hospital_expire_flag = 1) AS num_deaths,
    COUNT(cfa.hadm_id) AS total_cabg_admissions,
    SAFE_DIVIDE(COUNTIF(cfa.hospital_expire_flag = 1), COUNT(cfa.hadm_id)) AS mortality_rate
FROM
    CABG_First_Admissions cfa;