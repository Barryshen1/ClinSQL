SELECT
    PERCENTILE_CONT(le.valuenum, 0.75) OVER () AS percentile_75th_platelet_on_discharge
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
        AND adm.subject_id = diag.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON adm.hadm_id = le.hadm_id
        AND adm.subject_id = le.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
WHERE
    p.gender = 'F'
    AND p.anchor_age = 87
    AND (
        diag.icd_code LIKE 'I60%' OR   -- Nontraumatic intracranial hemorrhage (ICD-10)
        diag.icd_code LIKE 'I61%' OR   -- Nontraumatic intracerebral hemorrhage (ICD-10)
        diag.icd_code LIKE 'I62%'      -- Other nontraumatic intracranial hemorrhage (ICD-10)
    )
    AND dli.label = 'Platelet Count'
    AND le.valuenum IS NOT NULL
    AND DATE(le.charttime) = DATE(adm.dischtime)
QUALIFY ROW_NUMBER() OVER () = 1;