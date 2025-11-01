WITH sepsis_males AS (
    SELECT DISTINCT p.subject_id
    FROM physionet-data.mimiciv_3_1_hosp.patients p
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON p.subject_id = di.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE p.gender = 'M'
      AND LOWER(d.long_title) LIKE '%sepsis%'
),
platelet_peaks AS (
    SELECT le.subject_id, MAX(le.valuenum) AS peak_platelet
    FROM physionet-data.mimiciv_3_1_hosp.labevents le
    JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
    WHERE LOWER(dl.label) = 'platelet count'
      AND le.valuenum IS NOT NULL
      AND le.subject_id IN (SELECT subject_id FROM sepsis_males)
    GROUP BY le.subject_id
)
SELECT APPROX_QUANTILES(peak_platelet, 100)[OFFSET(75)] AS platelet_75th_percentile
FROM platelet_peaks;