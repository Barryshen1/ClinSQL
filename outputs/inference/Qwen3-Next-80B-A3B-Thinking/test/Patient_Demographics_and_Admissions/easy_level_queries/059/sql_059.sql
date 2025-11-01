WITH qualifying_admissions AS (
    SELECT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc ON a.hadm_id = proc.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE p.gender = 'F'
      AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 59 AND 69
      AND (d_proc.long_title LIKE '%PCI%' OR d_proc.long_title LIKE '%coronary angioplasty%' OR d_proc.long_title LIKE '%angioplasty%')
)
SELECT MAX(max_los) AS max_icu_los
FROM (
    SELECT i.hadm_id, MAX(i.los) AS max_los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN qualifying_admissions qa ON i.hadm_id = qa.hadm_id
    GROUP BY i.hadm_id
) AS max_los_per_admission;