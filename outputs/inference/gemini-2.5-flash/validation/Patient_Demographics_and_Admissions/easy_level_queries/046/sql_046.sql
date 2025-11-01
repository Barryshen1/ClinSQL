WITH PatientFirstAdmission AS (
    -- Select patients within the specified age and gender range for their first admission
    SELECT
        p.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.hospital_expire_flag,
        ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY ad.admittime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 37 AND 47
),
EligibleFirstAdmissions AS (
    SELECT
        subject_id,
        hadm_id,
        hospital_expire_flag
    FROM
        PatientFirstAdmission
    WHERE
        rn = 1
),
DAPTDrugIdentification AS (
    -- Identify prescriptions for Aspirin and P2Y12 inhibitors
    SELECT
        pr.subject_id,
        pr.hadm_id,
        CASE
            WHEN LOWER(pr.drug) LIKE '%aspirin%' OR LOWER(pr.drug) LIKE '%asa%' THEN 'Aspirin'
            WHEN LOWER(pr.drug) LIKE '%clopidogrel%' OR LOWER(pr.drug) LIKE '%plavix%' THEN 'P2Y12 Inhibitor'
            WHEN LOWER(pr.drug) LIKE '%ticagrelor%' OR LOWER(pr.drug) LIKE '%brilinta%' THEN 'P2Y12 Inhibitor'
            WHEN LOWER(pr.drug) LIKE '%prasugrel%' OR LOWER(pr.drug) LIKE '%effient%' THEN 'P2Y12 Inhibitor'
            ELSE NULL
        END AS drug_category
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    WHERE
        pr.drug IS NOT NULL AND (
            LOWER(pr.drug) LIKE '%aspirin%' OR LOWER(pr.drug) LIKE '%asa%'
            OR LOWER(pr.drug) LIKE '%clopidogrel%' OR LOWER(pr.drug) LIKE '%plavix%'
            OR LOWER(pr.drug) LIKE '%ticagrelor%' OR LOWER(pr.drug) LIKE '%brilinta%'
            OR LOWER(pr.drug) LIKE '%prasugrel%' OR LOWER(pr.drug) LIKE '%effient%'
        )
),
DAPTAdmissions AS (
    -- Filter for admissions where both Aspirin and a P2Y12 Inhibitor were prescribed
    SELECT
        subject_id,
        hadm_id
    FROM
        DAPTDrugIdentification
    GROUP BY
        subject_id,
        hadm_id
    HAVING
        COUNT(DISTINCT CASE WHEN drug_category = 'Aspirin' THEN 1 END) >= 1
        AND COUNT(DISTINCT CASE WHEN drug_category = 'P2Y12 Inhibitor' THEN 1 END) >= 1
)
-- Calculate the standard deviation of in-hospital mortality for the final cohort
SELECT
    STDDEV(efa.hospital_expire_flag) AS sd_in_hospital_mortality
FROM
    EligibleFirstAdmissions efa
INNER JOIN
    DAPTAdmissions da
    ON efa.subject_id = da.subject_id AND efa.hadm_id = da.hadm_id;