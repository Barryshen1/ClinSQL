WITH SepsisMaleAdmissions AS (
    SELECT DISTINCT adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE
        pat.gender = 'M'
        AND (
            -- Filter for common ICD-10 sepsis codes
            diag.icd_code LIKE 'A40%' OR
            diag.icd_code LIKE 'A41%'
        )
),
FirstPlatelet AS (
    SELECT
        le.hadm_id,
        le.valuenum,
        ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) as rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN SepsisMaleAdmissions sma
        ON le.hadm_id = sma.hadm_id
    WHERE
        le.itemid = 51265 -- Itemid for Platelet Count (verified via d_labitems to be "Platelets")
        AND le.valuenum IS NOT NULL -- Exclude null values
        AND le.valuenum > 0     -- Exclude non-positive or erroneous zero values
)
SELECT
    STDDEV(fp.valuenum) AS sd_admission_platelet_count -- Calculate the standard deviation
FROM FirstPlatelet fp
WHERE fp.rn = 1; -- Select only the first platelet count for each admission;