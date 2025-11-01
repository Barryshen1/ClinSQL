WITH cns_depressant_drugs AS (
    -- Define a list of common CNS depressant drugs
    -- This list is illustrative and would ideally be comprehensive based on clinical guidelines.
    SELECT * FROM UNNEST(['lorazepam', 'diazepam', 'midazolam', 'propofol', 'morphine', 'fentanyl', 'oxycodone', 'hydrocodone', 'codeine', 'alprazolam', 'clonazepam', 'zolpidem', 'eszopiclone', 'zaleplon']) AS drug_name
),
nephrotoxic_drugs AS (
    -- Define a list of common nephrotoxic drugs
    -- This list is illustrative and would ideally be comprehensive based on clinical guidelines.
    SELECT * FROM UNNEST(['ibuprofen', 'naproxen', 'diclofenac', 'ketorolac', 'indomethacin', 'gentamicin', 'tobramycin', 'amikacin', 'vancomycin', 'lisinopril', 'enalapril', 'ramipril', 'valsartan', 'losartan', 'irbesartan', 'telmisartan', 'captopril']) AS drug_name
),
patient_cohort AS (
    -- Select female inpatients aged 81-91
    SELECT
        p.subject_id,
        adm.hadm_id,
        -- Calculate age at admission
        EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age AS admission_age,
        adm.admittime,
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'F'
        AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 81 AND 91
        AND adm.admission_type IN ('EMERGENCY', 'URGENT', 'DIRECT EMER.', 'ELECTIVE')
),
aki_admissions AS (
    -- Filter patient cohort for AKI diagnosis
    SELECT DISTINCT
        pc.subject_id,
        pc.hadm_id,
        pc.admission_age,
        pc.admittime,
        pc.dischtime,
        pc.los_days,
        pc.hospital_expire_flag
    FROM
        patient_cohort pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON pc.subject_id = di.subject_id AND pc.hadm_id = di.hadm_id
    WHERE
        (di.icd_version = 9 AND di.icd_code BETWEEN '5840' AND '5849') -- AKI ICD-9 codes (e.g., 584.5 Acute kidney failure, unspecified)
        OR (di.icd_version = 10 AND SPLIT(di.icd_code, '.')[OFFSET(0)] = 'N17') -- AKI ICD-10 codes (e.g., N17.9 Acute kidney injury, unspecified)
),
medication_exposure AS (
    -- For each AKI admission, determine drug exposure and complexity
    SELECT
        aki.subject_id,
        aki.hadm_id,
        aki.los_days,
        aki.hospital_expire_flag,
        COUNT(DISTINCT p.drug) AS medication_complexity_score,
        MAX(CASE WHEN cns.drug_name IS NOT NULL THEN 1 ELSE 0 END) AS has_cns_depressant,
        MAX(CASE WHEN neph.drug_name IS NOT NULL THEN 1 ELSE 0 END) AS has_nephrotoxic
    FROM
        aki_admissions aki
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON aki.subject_id = p.subject_id
        AND aki.hadm_id = p.hadm_id
        AND p.drug IS NOT NULL -- Exclude prescriptions without a drug name
        AND p.drug_type = 'MAIN' -- Focus on main medication orders
    LEFT JOIN
        cns_depressant_drugs cns
        ON lower(p.drug) LIKE '%' || lower(cns.drug_name) || '%' -- Case-insensitive partial match for CNS drugs
    LEFT JOIN
        nephrotoxic_drugs neph
        ON lower(p.drug) LIKE '%' || lower(neph.drug_name) || '%' -- Case-insensitive partial match for nephrotoxic drugs
    GROUP BY
        aki.subject_id, aki.hadm_id, aki.los_days, aki.hospital_expire_flag
),
grouped_med_exposure AS (
    -- Assign each admission to one of the two comparison groups
    SELECT
        subject_id,
        hadm_id,
        los_days,
        hospital_expire_flag,
        medication_complexity_score,
        CASE
            WHEN has_cns_depressant = 1 AND has_nephrotoxic = 1 THEN 'CNS+Nephrotoxic'
            ELSE 'Other AKI'
        END AS exposure_group
    FROM
        medication_exposure
),
group_summary AS (
    -- Aggregate statistics for each exposure group
    SELECT
        exposure_group,
        COUNT(DISTINCT hadm_id) AS num_admissions,
        AVG(medication_complexity_score) AS mean_med_complexity,
        -- Quartiles for medication complexity
        APPROX_QUANTILES(medication_complexity_score, 100)[OFFSET(25)] AS med_complexity_q1,
        APPROX_QUANTILES(medication_complexity_score, 100)[OFFSET(50)] AS med_complexity_median,
        APPROX_QUANTILES(medication_complexity_score, 100)[OFFSET(75)] AS med_complexity_q3,
        AVG(los_days) AS mean_los_days,
        SUM(hospital_expire_flag) / COUNT(hadm_id) AS overall_mortality_rate,
        -- Get the 75th percentile of LOS for this group, to define "top-quartile LOS"
        APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_q3_value
    FROM
        grouped_med_exposure
    GROUP BY
        exposure_group
),
top_los_mortality AS (
    -- Calculate mortality specifically for patients in the top 25% of LOS within each group
    SELECT
        gme.exposure_group,
        SUM(gme.hospital_expire_flag) AS top_los_deaths,
        COUNT(gme.hadm_id) AS top_los_patients
    FROM
        grouped_med_exposure gme
    INNER JOIN
        group_summary gs
        ON gme.exposure_group = gs.exposure_group
    WHERE
        gme.los_days >= gs.los_q3_value -- Filter for patients with LOS at or above the 75th percentile
    GROUP BY
        gme.exposure_group
)
-- Final selection of all required statistics
SELECT
    gs.exposure_group,
    gs.num_admissions,
    gs.mean_med_complexity,
    gs.med_complexity_q1,
    gs.med_complexity_median,
    gs.med_complexity_q3,
    gs.mean_los_days,
    gs.overall_mortality_rate,
    gs.los_q3_value, -- The minimum LOS for the top quartile
    COALESCE(tlm.top_los_deaths / tlm.top_los_patients, 0) AS top_quartile_los_mortality_rate
FROM
    group_summary gs
LEFT JOIN
    top_los_mortality tlm
    ON gs.exposure_group = tlm.exposure_group
ORDER BY
    gs.exposure_group;