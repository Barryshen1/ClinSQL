WITH AMI_Cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 67 AND 77
    AND adm.hadm_id IN ( -- Ensure at least one AMI diagnosis during this admission
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        WHERE
            (diag.icd_version = 9 AND diag.icd_code LIKE '410%') -- ICD-9 AMI codes (e.g., 410.x Acute MI)
            OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%') -- ICD-10 AMI codes (e.g., I21.x Acute MI)
    )
),
MedicationComplexity AS (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        COUNT(DISTINCT prs.drug) AS med_complexity_score
    FROM
        AMI_Cohort ac
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` prs
        ON ac.subject_id = prs.subject_id
        AND ac.hadm_id = prs.hadm_id
        AND prs.starttime BETWEEN ac.admittime AND TIMESTAMP_ADD(ac.admittime, INTERVAL 24 HOUR)
    GROUP BY
        ac.subject_id, ac.hadm_id
),
-- Identify subsequent admissions for 30-day readmission calculation
Admissions_With_Next_Admit_Time AS (
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
),
Cohort_With_Readmission AS (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.admittime,
        ac.dischtime,
        ac.hospital_expire_flag,
        awna.next_admittime,
        -- A readmission is defined as an admission within 30 days (1 to 30 days) of discharge
        CASE
            WHEN awna.next_admittime IS NOT NULL
                 AND DATE_DIFF(CAST(awna.next_admittime AS DATE), CAST(ac.dischtime AS DATE), DAY) BETWEEN 1 AND 30
            THEN 1
            ELSE 0
        END AS readmission_30d_flag
    FROM
        AMI_Cohort ac
    INNER JOIN
        Admissions_With_Next_Admit_Time awna
        ON ac.subject_id = awna.subject_id AND ac.hadm_id = awna.hadm_id
),
AdmissionData AS (
    SELECT
        chr.subject_id,
        chr.hadm_id,
        -- Calculate Length of Stay in days
        DATE_DIFF(CAST(chr.dischtime AS DATE), CAST(chr.admittime AS DATE), DAY) AS los_days,
        chr.hospital_expire_flag,
        chr.readmission_30d_flag,
        -- Use COALESCE to set score to 0 if no medications were found in the first 24 hours
        COALESCE(mc.med_complexity_score, 0) AS med_complexity_score
    FROM
        Cohort_With_Readmission chr
    LEFT JOIN
        MedicationComplexity mc
        ON chr.hadm_id = mc.hadm_id
    WHERE
        chr.dischtime IS NOT NULL -- Exclude ongoing admissions for LOS and readmission calculations
),
AdmissionDataWithTertile AS (
    SELECT
        subject_id,
        hadm_id,
        complexity_tertile,
        los_days,
        hospital_expire_flag,
        readmission_30d_flag,
        med_complexity_score
    FROM (
        SELECT
            *,
            NTILE(3) OVER (ORDER BY med_complexity_score) AS complexity_tertile
        FROM
            AdmissionData
        )
)
SELECT
    complexity_tertile,
    COUNT(hadm_id) AS admission_count,
    MIN(med_complexity_score) AS score_min,
    MAX(med_complexity_score) AS score_max,
    AVG(med_complexity_score) AS score_mean,
    AVG(los_days) AS mean_los_days,
    AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
    AVG(readmission_30d_flag) * 100 AS readmission_30d_percent
FROM
    AdmissionDataWithTertile
GROUP BY
    complexity_tertile
ORDER BY
    complexity_tertile;