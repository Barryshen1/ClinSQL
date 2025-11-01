WITH FemaleAgeFilteredAdmissions AS (
    SELECT
        p.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 84 AND 90 -- Patients with anchor_age 84-90 represent actual ages 84-90+ due to privacy anonymization (capped at 90).
),
EchocardiographyICDCodes AS (
    SELECT DISTINCT
        icd_code,
        icd_version
    FROM
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE
        LOWER(long_title) LIKE '%echo%'
        OR LOWER(long_title) LIKE '%cardiac ultrasound%'
        OR LOWER(long_title) LIKE '%ultrasound of heart%'
),
HospitalizationEchoCounts AS (
    SELECT
        f.subject_id,
        f.hadm_id,
        -- Count distinct ICD codes ONLY if they are identified as Echocardiography.
        -- If no matching echo procedure, COUNT(DISTINCT eicd.icd_code) will be 0 because eicd.icd_code from a LEFT JOIN would be NULL.
        COUNT(DISTINCT eicd.icd_code) AS num_distinct_echos
    FROM
        FemaleAgeFilteredAdmissions f
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
        ON f.subject_id = pr.subject_id AND f.hadm_id = pr.hadm_id
    LEFT JOIN
        EchocardiographyICDCodes eicd
        ON pr.icd_code = eicd.icd_code AND pr.icd_version = eicd.icd_version
    GROUP BY
        f.subject_id,
        f.hadm_id
)
SELECT
    PERCENTILE_CONT(num_distinct_echos, 0.25) AS p25_distinct_echos_per_hospitalization
FROM
    HospitalizationEchoCounts;