WITH AdmittedPatients AS (
    -- Step 1: Identify eligible female ICU patients aged 88-98
    SELECT DISTINCT
        icu.subject_id,
        icu.stay_id,
        icu.intime
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON icu.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 88 AND 98
),
HFNCPatients AS (
    -- Step 2: Filter these patients to those who received high-flow nasal cannula
    -- itemid 227209 is common for 'High flow nasal cannula' in chartevents
    SELECT DISTINCT
        ap.subject_id,
        ap.stay_id,
        ap.intime
    FROM AdmittedPatients ap
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce_hfnc
        ON ap.stay_id = ce_hfnc.stay_id
    WHERE
        ce_hfnc.itemid = 227209
        AND ce_hfnc.valuenum IS NOT NULL -- Assuming valuenum being present indicates use
                                       -- or checking value like 'High Flow Nasal Cannula'
),
GCSData AS (
    -- Step 3: Get GCS totals for the HFNCPatients on ICU Day 2 or later
    SELECT
        ce_gcs.valuenum AS gcs_total
    FROM HFNCPatients hfn
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce_gcs
        ON hfn.stay_id = ce_gcs.stay_id
    WHERE
        ce_gcs.itemid = 227013 -- GCS - Total (Adult)
        AND ce_gcs.valuenum IS NOT NULL
        AND ce_gcs.valuenum BETWEEN 3 AND 15 -- Valid GCS range
        AND DATE_DIFF(DATE(ce_gcs.charttime), DATE(hfn.intime), DAY) >= 2 -- ICU Day 2 or later (Day 0 is intime day, Day 1 is next day, Day 2 is two days later)
)
-- Step 4: Calculate the median GCS total and address the "are there any" part
SELECT
    CASE
        WHEN COUNT(gcs.gcs_total) = 0 THEN 'No GCS scores found for the filtered population on ICU Day 2 or later.'
        ELSE CAST(PERCENTILE_CONT(gcs.gcs_total, 0.5) AS STRING) -- Corrected PERCENTILE_CONT usage as an aggregate function
    END AS median_gcs_total
FROM GCSData gcs;