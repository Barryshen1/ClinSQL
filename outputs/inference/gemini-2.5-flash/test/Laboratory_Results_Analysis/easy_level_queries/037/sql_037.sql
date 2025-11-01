WITH SepsisAdmissions AS (
    -- Identify unique admissions for 43-year-old male patients with a sepsis diagnosis
    SELECT
        ad.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age = 43 -- Filter for 43-year-old men based on anchor_age
        AND (
            -- Common ICD-10 codes for sepsis (A40-A41 range)
            (di.icd_version = 10 AND (di.icd_code LIKE 'A40%' OR di.icd_code LIKE 'A41%'))
            -- Common ICD-9 codes for septicemia (038 range)
            OR
            (di.icd_version = 9 AND di.icd_code LIKE '038%')
        )
    GROUP BY
        ad.subject_id,
        ad.hadm_id
),
PeakPlatelet AS (
    -- Calculate the peak platelet count for each qualifying admission
    SELECT
        sa.subject_id,
        sa.hadm_id,
        MAX(le.valuenum) AS peak_platelet_count
    FROM
        SepsisAdmissions sa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON sa.subject_id = le.subject_id AND sa.hadm_id = le.hadm_id
    WHERE
        le.itemid = 51265 -- Confirmed itemid for 'Platelet Count' in d_labitems
        AND le.valuenum IS NOT NULL
        AND le.valuenum > 0 -- Exclude invalid or zero/negative values
    GROUP BY
        sa.subject_id,
        sa.hadm_id
)
-- Calculate the 75th percentile of these peak platelet counts
SELECT
    PERCENTILE_CONT(peak_platelet_count, 0.75) AS q75_peak_platelet_count
FROM
    PeakPlatelet;