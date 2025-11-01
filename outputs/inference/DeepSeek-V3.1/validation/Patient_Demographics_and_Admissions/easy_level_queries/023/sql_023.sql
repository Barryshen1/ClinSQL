WITH pci_patients AS (
    SELECT DISTINCT p.subject_id, p.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE d.icd_code LIKE '02%'  -- ICD-10 PCI procedures start with '02'
)
SELECT 
    APPROX_QUANTILES(i.los, 2)[OFFSET(1)] AS median_icu_los_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` i
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON i.subject_id = pt.subject_id
INNER JOIN pci_patients pp
    ON i.subject_id = pp.subject_id AND i.hadm_id = pp.hadm_id
WHERE pt.gender = 'M'
    AND pt.anchor_age BETWEEN 68 AND 78;