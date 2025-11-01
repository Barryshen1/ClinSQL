WITH AdmissionsWithAge AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.hospital_expire_flag,
        -- Assign a row number to each admission for a patient, ordered by admission time
        -- This helps identify the first admission (rn = 1)
        ROW_NUMBER() OVER (PARTITION BY ad.subject_id ORDER BY ad.admittime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M' -- Filter for male patients
        AND p.anchor_age BETWEEN 48 AND 58 -- Filter for age range 48-58
),
CABG_Admissions AS (
    SELECT DISTINCT
        pr.subject_id,
        pr.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
        ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
    WHERE
        (
            -- ICD-9-CM codes for Coronary Artery Bypass Graft (CABG)
            pr.icd_version = 9 AND pr.icd_code IN ('36.10', '36.11', '36.12', '36.13', '36.14', '36.15', '36.16', '36.17', '36.19')
        )
        OR
        (
            -- ICD-10-PCS codes for Bypass Coronary Artery (specific for CABG, filtering by title for precision)
            pr.icd_version = 10 AND pr.icd_code LIKE '021%' AND dp.long_title LIKE '%Bypass Coronary Artery%'
        )
)
SELECT
    -- Calculate the 25th percentile of in-hospital mortality for the filtered cohort
    PERCENTILE_DISC(t1.hospital_expire_flag, 0.25) OVER () AS q25_in_hospital_mortality
FROM
    AdmissionsWithAge t1
INNER JOIN
    CABG_Admissions t2
    ON t1.subject_id = t2.subject_id AND t1.hadm_id = t2.hadm_id
WHERE
    t1.rn = 1; -- Select only the first admission for each patient;