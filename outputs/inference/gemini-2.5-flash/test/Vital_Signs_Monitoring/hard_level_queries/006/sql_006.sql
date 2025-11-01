WITH ugib_cohort AS (
    -- Define the target cohort: male ICU patients aged 60-70 with UGIB
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los,
        adm.hospital_expire_flag,
        pat.gender,
        (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.subject_id = adm.subject_id AND ie.hadm_id = adm.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ie.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 60 AND 70
        AND EXISTS ( -- Check for UGIB diagnosis (Upper Gastrointestinal Bleeding)
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.subject_id = ie.subject_id
                AND di.hadm_id = ie.hadm_id
                AND di.icd_version IN (9, 10)
                AND (
                    -- Common ICD-9 codes for UGIB (Hematemesis, Melena, GI hemorrhage unspecified)
                    (di.icd_version = 9 AND di.icd_code IN ('5780', '5781', '5789'))
                    -- Common ICD-10 codes for UGIB (Hematemesis, Melena, GI hemorrhage unspecified)
                    OR (di.icd_version = 10 AND di.icd_code IN ('K920', 'K921', 'K922'))
                )
        )
),
vital_instability_scores AS (
    -- Calculate the 48-hour vital instability index for each patient in the cohort
    -- Index is defined as the count of individual unstable vital sign measurements within the first 48 hours of ICU stay.
    SELECT
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        COUNT(
            CASE
                WHEN ce.itemid = 220045 AND ce.valuenum IS NOT NULL AND ce.valuenum > 100 THEN 1 -- Heart Rate > 100 bpm (Tachycardia)
                WHEN ce.itemid = 220052 AND ce.valuenum IS NOT NULL AND ce.valuenum < 65 THEN 1 -- MAP < 65 mmHg (Hypotension)
                WHEN ce.itemid = 220210 AND ce.valuenum IS NOT NULL AND ce.valuenum > 20 THEN 1 -- Respiratory Rate > 20 bpm (Tachypnea)
                -- Temperature Conversion: (Fahrenheit - 32) * 5/9 = Celsius
                WHEN ce.itemid = 223761 AND ce.valuenum IS NOT NULL AND ((ce.valuenum - 32) * 5/9) < 36 THEN 1 -- Temp < 36C (Hypothermia)
                WHEN ce.itemid = 223761 AND ce.valuenum IS NOT NULL AND ((ce.valuenum - 32) * 5/9) > 38 THEN 1 -- Temp > 38C (Fever)
                WHEN ce.itemid = 223762 AND ce.valuenum IS NOT NULL AND ce.valuenum < 36 THEN 1 -- Temp < 36C (Hypothermia)
                WHEN ce.itemid = 223762 AND ce.valuenum IS NOT NULL AND ce.valuenum > 38 THEN 1 -- Temp > 38C (Fever)
                ELSE NULL
            END
        ) AS vital_instability_index_48hr
    FROM
        ugib_cohort c
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.subject_id = ce.subject_id AND c.hadm_id = ce.hadm_id AND c.stay_id = ce.stay_id
    WHERE
        ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
        AND ce.valuenum IS NOT NULL -- Ensure numeric value for vital signs
    GROUP BY
        c.subject_id, c.hadm_id, c.stay_id
),
cohort_with_index_and_percentiles AS (
    -- Combine cohort data with calculated index and calculate percentiles across the cohort
    SELECT
        c.*,
        -- Use COALESCE to assign 0 instability if no relevant chart events found or no instability recorded
        COALESCE(vis.vital_instability_index_48hr, 0) AS vital_instability_index_48hr,
        -- Corrected PERCENTILE_CONT usage
        PERCENTILE_CONT(COALESCE(vis.vital_instability_index_48hr, 0), 0.95) OVER() AS p95_vital_instability,
        PERCENTILE_CONT(COALESCE(vis.vital_instability_index_48hr, 0), 0.90) OVER() AS p90_vital_instability -- Threshold for top decile
    FROM
        ugib_cohort c
    LEFT JOIN
        vital_instability_scores vis
        ON c.subject_id = vis.subject_id AND c.hadm_id = vis.hadm_id AND c.stay_id = vis.stay_id
),
patient_groups_and_outcomes AS (
    -- Assign patients to 'Top Decile' or 'Control Group' and include full stay outcomes
    SELECT
        ci.subject_id,
        ci.hadm_id,
        ci.stay_id,
        ci.los,
        ci.hospital_expire_flag,
        ci.vital_instability_index_48hr,
        ci.p95_vital_instability,
        ci.p90_vital_instability,
        CASE
            WHEN ci.vital_instability_index_48hr >= ci.p90_vital_instability THEN 'Top Decile'
            ELSE 'Control Group'
        END AS patient_group
    FROM
        cohort_with_index_and_percentiles ci
),
vital_sign_occurrences_full_stay AS (
    -- Calculate specific vital sign occurrences over the entire ICU stay for each patient for comparison
    SELECT
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum IS NOT NULL AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS ever_tachycardia,
        MAX(CASE WHEN ce.itemid = 220052 AND ce.valuenum IS NOT NULL AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS ever_hypotension_map,
        MAX(CASE WHEN ce.itemid = 220210 AND ce.valuenum IS NOT NULL AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS ever_tachypnea
    FROM
        ugib_cohort c
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.subject_id = ce.subject_id AND c.hadm_id = ce.hadm_id AND c.stay_id = ce.stay_id
    WHERE
        ce.charttime BETWEEN c.intime AND c.outtime -- Over entire ICU stay
        AND ce.valuenum IS NOT NULL
        AND ce.itemid IN (220045, 220052, 220210) -- Only consider relevant itemids for these outcomes
    GROUP BY
        c.subject_id, c.hadm_id, c.stay_id
)
-- Final result: Present the 95th percentile and compare outcomes between top decile and control groups
SELECT
    '95th Percentile of 48-hour Vital Instability Index' AS metric,
    CAST(ROUND(MAX(pgo.p95_vital_instability), 2) AS STRING) AS value_or_count,
    NULL AS top_decile_value,
    NULL AS control_value
FROM
    patient_groups_and_outcomes pgo

UNION ALL

SELECT
    'Average ICU LOS (days)' AS metric,
    NULL AS value_or_count,
    ROUND(AVG(CASE WHEN pgo.patient_group = 'Top Decile' THEN pgo.los ELSE NULL END), 2) AS top_decile_value,
    ROUND(AVG(CASE WHEN pgo.patient_group = 'Control Group' THEN pgo.los ELSE NULL END), 2) AS control_value
FROM
    patient_groups_and_outcomes pgo

UNION ALL

SELECT
    'Mortality Rate (%)' AS metric,
    NULL AS value_or_count,
    ROUND(AVG(CASE WHEN pgo.patient_group = 'Top Decile' THEN pgo.hospital_expire_flag ELSE NULL END) * 100, 2) AS top_decile_value,
    ROUND(AVG(CASE WHEN pgo.patient_group = 'Control Group' THEN pgo.hospital_expire_flag ELSE NULL END) * 100, 2) AS control_value
FROM
    patient_groups_and_outcomes pgo

UNION ALL

SELECT
    'Patients with Tachycardia > 100 (%)' AS metric,
    NULL AS value_or_count,
    ROUND(AVG(CASE WHEN pgo.patient_group = 'Top Decile' THEN vso.ever_tachycardia ELSE NULL END) * 100, 2) AS top_decile_value,
    ROUND(AVG(CASE WHEN pgo.patient_group = 'Control Group' THEN vso.ever_tachycardia ELSE NULL END) * 100, 2) AS control_value
FROM
    patient_groups_and_outcomes pgo
INNER JOIN -- Inner join is safe as vital_sign_occurrences_full_stay covers all cohort members
    vital_sign_occurrences_full_stay vso
    ON pgo.subject_id = vso.subject_id AND pgo.hadm_id = vso.hadm_id AND pgo.stay_id = vso.stay_id

UNION ALL

SELECT
    'Patients with MAP < 65 (%)' AS metric,
    NULL AS value_or_count,
    ROUND(AVG(CASE WHEN pgo.patient_group = 'Top Decile' THEN vso.ever_hypotension_map ELSE NULL END) * 100, 2) AS top_decile_value,
    ROUND(AVG(CASE WHEN pgo.patient_group = 'Control Group' THEN vso.ever_hypotension_map ELSE NULL END) * 100, 2) AS control_value
FROM
    patient_groups_and_outcomes pgo
INNER JOIN
    vital_sign_occurrences_full_stay vso
    ON pgo.subject_id = vso.subject_id AND pgo.hadm_id = vso.hadm_id AND pgo.stay_id = vso.stay_id

UNION ALL

SELECT
    'Patients with Tachypnea > 20 (%)' AS metric,
    NULL AS value_or_count,
    ROUND(AVG(CASE WHEN pgo.patient_group = 'Top Decile' THEN vso.ever_tachypnea ELSE NULL END) * 100, 2) AS top_decile_value,
    ROUND(AVG(CASE WHEN pgo.patient_group = 'Control Group' THEN vso.ever_tachypnea ELSE NULL END) * 100, 2) AS control_value
FROM
    patient_groups_and_outcomes pgo
INNER JOIN
    vital_sign_occurrences_full_stay vso
    ON pgo.subject_id = vso.subject_id AND pgo.hadm_id = vso.hadm_id AND pgo.stay_id = vso.stay_id
ORDER BY
    metric;