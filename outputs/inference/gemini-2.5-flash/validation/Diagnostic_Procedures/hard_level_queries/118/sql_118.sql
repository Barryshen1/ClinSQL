WITH AdmissionsFiltered AS (
    -- Step 1 & 2: Identify female ICU admissions aged 44-54 with AMI.
    -- Calculate effective age at admission and rank ICU stays for each admission.
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        icu.stay_id,
        icu.intime AS icu_intime,
        ROW_NUMBER() OVER (PARTITION BY adm.subject_id, adm.hadm_id ORDER BY icu.intime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN (
        -- Subquery to select admissions with Acute Myocardial Infarction (AMI) diagnosis
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE
            (di.icd_version = 9 AND STARTS_WITH(di.icd_code, '410')) -- ICD-9 AMI
            OR (di.icd_version = 10 AND (STARTS_WITH(di.icd_code, 'I21') OR STARTS_WITH(di.icd_code, 'I22'))) -- ICD-10 AMI
    ) AS ami_diag
        ON adm.hadm_id = ami_diag.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.subject_id = icu.subject_id
        AND adm.hadm_id = icu.hadm_id
    WHERE
        pat.gender = 'F'
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 44 AND 54
        AND icu.intime IS NOT NULL -- Ensure a valid ICU start time
),
FirstICUStayCohort AS (
    -- Filter for only the first ICU stay for each qualifying admission
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        stay_id,
        icu_intime
    FROM AdmissionsFiltered
    WHERE rn = 1
),
Procedures72h AS (
    -- Step 3: Calculate procedure count in the first 72 hours of the first ICU stay.
    SELECT
        fics.subject_id,
        fics.hadm_id,
        fics.stay_id,
        COUNT(pe.itemid) AS procedure_count_72h
    FROM
        `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    INNER JOIN
        FirstICUStayCohort fics
        ON pe.subject_id = fics.subject_id
        AND pe.hadm_id = fics.hadm_id
        AND pe.stay_id = fics.stay_id
    WHERE
        pe.starttime >= fics.icu_intime
        AND pe.starttime < DATETIME_ADD(fics.icu_intime, INTERVAL 72 HOUR)
    GROUP BY
        fics.subject_id, fics.hadm_id, fics.stay_id
)
-- Final SELECT to stratify and report requested metrics
SELECT
    procedure_quartile,
    COUNT(t.subject_id) AS n_per_quartile, -- Number of qualifying first ICU stays/admissions in this quartile
    AVG(t.procedure_count_72h) AS mean_procedure_count,
    AVG(DATETIME_DIFF(t.dischtime, t.admittime, HOUR) / 24.0) AS avg_hospital_los_days,
    SUM(CASE WHEN t.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(t.subject_id) AS in_hospital_mortality_pct
FROM (
    SELECT
        fics.subject_id,
        fics.hadm_id,
        fics.admittime,
        fics.dischtime,
        fics.hospital_expire_flag,
        COALESCE(p72.procedure_count_72h, 0) AS procedure_count_72h, -- Use COALESCE to treat NULL as 0 procedures
        NTILE(4) OVER (ORDER BY COALESCE(p72.procedure_count_72h, 0)) AS procedure_quartile
    FROM
        FirstICUStayCohort fics
    LEFT JOIN
        Procedures72h p72
        ON fics.subject_id = p72.subject_id
        AND fics.hadm_id = p72.hadm_id
        AND fics.stay_id = p72.stay_id
) AS t
GROUP BY
    procedure_quartile
ORDER BY
    procedure_quartile;