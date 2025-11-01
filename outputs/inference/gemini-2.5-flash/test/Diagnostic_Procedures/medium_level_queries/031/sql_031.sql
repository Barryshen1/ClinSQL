WITH AKI_Patient_Admissions AS (
    -- First, identify all admissions for female patients aged 38-48 with an AKI diagnosis
    SELECT
        pa.subject_id,
        ad.hadm_id,
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 38 AND 48
        -- Ensure the admission has an Acute Kidney Injury (AKI) diagnosis
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.subject_id = pa.subject_id
                AND di.hadm_id = ad.hadm_id
                AND (
                    (di.icd_version = 10 AND di.icd_code LIKE 'N17%') -- ICD-10 codes for AKI
                    OR (di.icd_version = 9 AND di.icd_code LIKE '584%') -- ICD-9 codes for AKI
                )
        )
),
Admission_Classification AS (
    -- Classify admissions based on Length of Stay and ICU presence
    SELECT
        apa.subject_id,
        apa.hadm_id,
        apa.los_days,
        CASE
            WHEN apa.los_days >= 1 AND apa.los_days <= 4 THEN '1-4 days'
            WHEN apa.los_days >= 5 AND apa.los_days <= 7 THEN '5-7 days'
            ELSE 'Other' -- Should be filtered out by the WHERE clause
        END AS admission_length_category,
        MAX(CASE WHEN icu.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END) AS icu_use
        -- Using MAX to assign 'ICU' if any ICU stay exists for the admission
    FROM
        AKI_Patient_Admissions apa
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON apa.subject_id = icu.subject_id AND apa.hadm_id = icu.hadm_id
    WHERE
        apa.los_days BETWEEN 1 AND 7 -- Restrict to stays between 1 and 7 days
    GROUP BY
        apa.subject_id,
        apa.hadm_id,
        apa.los_days
),
Lab_Events_Counts AS (
    -- Count lab events per admission
    SELECT
        le.hadm_id,
        COUNT(le.labevent_id) AS lab_diag_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    WHERE
        le.hadm_id IN (SELECT hadm_id FROM Admission_Classification)
    GROUP BY
        le.hadm_id
),
Microbiology_Events_Counts AS (
    -- Count microbiology events per admission
    SELECT
        me.hadm_id,
        COUNT(me.microevent_id) AS micro_diag_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.microbiologyevents` me
    WHERE
        me.hadm_id IN (SELECT hadm_id FROM Admission_Classification)
    GROUP BY
        me.hadm_id
),
Chartevents_Non_Invasive_Counts AS (
    -- Count relevant non-invasive chartevents per admission
    SELECT
        ce.hadm_id,
        COUNT(ce.charttime) AS chartevents_diag_count
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN
        `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ce.itemid = di.itemid
    WHERE
        ce.hadm_id IN (SELECT hadm_id FROM Admission_Classification)
        AND di.linksto = 'chartevents'
        AND di.category IN (
            'Routine Vital Signs',
            'Pain',
            'Pulmonary',
            'Neurological',
            'General',
            'Admission Assessments',
            'GI/GU',
            'Respiratory'
        )
    GROUP BY
        ce.hadm_id
),
Outputevents_Counts AS (
    -- Count outputevents per admission
    SELECT
        oe.hadm_id,
        COUNT(oe.charttime) AS output_diag_count
    FROM
        `physionet-data.mimiciv_3_1_icu.outputevents` oe
    WHERE
        oe.hadm_id IN (SELECT hadm_id FROM Admission_Classification)
    GROUP BY
        oe.hadm_id
),
Combined_Diagnostic_Counts AS (
    -- Combine all non-invasive diagnostic counts for each admission
    SELECT
        ac.hadm_id,
        ac.admission_length_category,
        ac.icu_use,
        COALESCE(lec.lab_diag_count, 0) +
        COALESCE(mec.micro_diag_count, 0) +
        COALESCE(cnic.chartevents_diag_count, 0) +
        COALESCE(oec.output_diag_count, 0) AS total_non_invasive_diagnostics
    FROM
        Admission_Classification ac
    LEFT JOIN
        Lab_Events_Counts lec ON ac.hadm_id = lec.hadm_id
    LEFT JOIN
        Microbiology_Events_Counts mec ON ac.hadm_id = mec.hadm_id
    LEFT JOIN
        Chartevents_Non_Invasive_Counts cnic ON ac.hadm_id = cnic.hadm_id
    LEFT JOIN
        Outputevents_Counts oec ON ac.hadm_id = oec.hadm_id
)
-- Final aggregation to calculate mean, min, and max for each category
SELECT
    admission_length_category,
    icu_use,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    ROUND(AVG(total_non_invasive_diagnostics), 2) AS mean_non_invasive_diagnostics_per_admission,
    MIN(total_non_invasive_diagnostics) AS min_non_invasive_diagnostics_per_admission,
    MAX(total_non_invasive_diagnostics) AS max_non_invasive_diagnostics_per_admission
FROM
    Combined_Diagnostic_Counts
GROUP BY
    admission_length_category,
    icu_use
ORDER BY
    admission_length_category,
    icu_use;